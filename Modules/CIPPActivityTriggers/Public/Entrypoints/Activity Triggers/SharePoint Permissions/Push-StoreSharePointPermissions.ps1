function Push-StoreSharePointPermissions {
    <#
    .SYNOPSIS
        Post-execution function that aggregates per-batch SharePoint permission rows and writes the cache.

    .DESCRIPTION
        Collects the Sites arrays returned by every Push-DBCacheSharePointPermissionsBatch activity,
        flattens their Site and Assignment rows into a single row set, and writes
        SharePointPermissions once via Add-CIPPDbItem.

        Partial-run tolerance: on a large tenant a whole batch can fail to return (throttling,
        timeout, worker reclaim), dropping its ~20 sites from the fan-in. Rather than discard the
        entire run, the sites that WERE collected are written fresh and every expected site that did
        not come back is carried over from the prior cache and flagged Skipped - the same treatment a
        per-site Skip already gets. This keeps the report (and its -Count row's timestamp) alive
        across the common case of one flaky batch instead of letting the whole cache expire under the
        30-day reporting retention. ExpectedSiteIds - passed by Set-CIPPDBCacheSharePointPermissions -
        is what lets a site whose batch failed (carry it over) be told apart from a site that no
        longer exists (let it fall out). An older in-flight orchestration queued before that parameter
        existed falls back to the previous all-or-nothing behaviour, because without the id set a
        short result set cannot be reconciled safely.

        No-progress guard: the write only happens when at least one site was actually collected this
        run. A run where nothing came back leaves the prior cache untouched - it is NOT rewritten with
        fresh timestamps (which would launder stale data past the retention window) and its -Count row
        is not restamped - so genuinely stale data still ages out and expires honestly.

        Memory: rows are streamed into a single Add-CIPPDbItem invocation (one invocation keeps its
        RunId-based orphan cleanup authoritative) and each site's collected rows are released as they
        are written, and the prior cache is read one site at a time (by RowKey prefix) only for the
        sites being restored - a 100k-assignment tenant OOMs the worker here otherwise.

        Row types written (see Push-DBCacheSharePointPermissionsBatch for the full schema):
        - rowType 'Site'        one per site, always present, carries collectionStatus and library counts
        - rowType 'Assignment'  one per scope, principal and permission level

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $ExpectedSiteCount = [int]$Item.Parameters.ExpectedSiteCount
    # The full expected site-id set, when the collector passed it. Present -> a site that is expected
    # but absent from the results is a failed batch (carry it over); one not in the set no longer
    # exists (drop it). Older orchestrations predate this parameter; see the fallback below.
    $ExpectedSiteIds = @($Item.Parameters.ExpectedSiteIds | Where-Object { $_ })
    $HaveExpectedIds = $ExpectedSiteIds.Count -gt 0

    try {
        $SiteResults = [System.Collections.Generic.List[object]]::new()
        foreach ($BatchResult in @($Item.Results)) {
            foreach ($SiteResult in @($BatchResult.Sites)) {
                if ($SiteResult) { $SiteResults.Add($SiteResult) }
            }
        }

        $ActualCount = $SiteResults.Count
        $ReturnedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $SkippedIds = [System.Collections.Generic.List[string]]::new()
        $CollectedCount = 0
        foreach ($SiteResult in $SiteResults) {
            $null = $ReturnedIds.Add([string]$SiteResult.SiteId)
            if ($SiteResult.CollectionStatus -eq 'Skipped') {
                $SkippedIds.Add([string]$SiteResult.SiteId)
            } else {
                $CollectedCount++
            }
        }

        # Nothing collected this run. Leave the prior cache untouched rather than restamp it with
        # fresh timestamps (which would hide stale data from the retention window) or write a fresh
        # -Count row over data we did not refresh.
        if ($CollectedCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SharePoint permissions: no sites collected this run for $TenantFilter (expected $ExpectedSiteCount, returned $ActualCount); prior cache left untouched" -sev Error
            return
        }

        # Expected sites that no batch returned a result for (the batch failed/was reclaimed).
        $MissingIds = [System.Collections.Generic.List[string]]::new()
        if ($HaveExpectedIds) {
            foreach ($Id in $ExpectedSiteIds) {
                if (-not $ReturnedIds.Contains([string]$Id)) { $MissingIds.Add([string]$Id) }
            }
        } elseif ($ActualCount -ne $ExpectedSiteCount) {
            # No expected-id set to reconcile against (pre-upgrade orchestration): a partial set can't
            # be told from deletions, and writing it would let replace-mode orphan cleanup delete the
            # missing sites' rows. Preserve the prior cache and wait for a complete run, as before.
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SharePoint permissions: incomplete result set for $TenantFilter (expected $ExpectedSiteCount, got $ActualCount) with no expected-site list to reconcile; prior cache left untouched" -sev Warning
            return
        }

        # Sites whose assignment rows must be restored from the prior cache: those that came back
        # Skipped, plus those that did not come back at all. Read each one on its own by RowKey prefix
        # so peak memory tracks the restore set, not the whole tenant.
        $RestoreIds = [System.Collections.Generic.List[string]]::new()
        foreach ($Id in $SkippedIds) { $RestoreIds.Add([string]$Id) }
        foreach ($Id in $MissingIds) { $RestoreIds.Add([string]$Id) }

        $PriorAssignmentsBySiteId = @{}
        $PriorSiteRowBySiteId = @{}
        if ($RestoreIds.Count -gt 0) {
            # Resolve the partition key exactly as Add-CIPPDbItem does so the read and the write agree.
            $DbTenant = $TenantFilter
            if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                try {
                    $Lookup = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)
                    if ($Lookup.Count -gt 0) { $DbTenant = $Lookup[0].defaultDomainName }
                } catch {}
            }
            $PartEsc = $DbTenant -replace "'", "''"
            $Table = Get-CippTable -tablename 'CippReportingDB'
            foreach ($Id in $RestoreIds) {
                $Key = [string]$Id
                # Match Add-CIPPDbItem's path-character RowKey sanitisation so the prefix lines up with
                # stored keys (site ids are otherwise clean ASCII). Every row for a site is keyed
                # 'SharePointPermissions-<siteId>_...', so that prefix returns exactly this site's Site
                # and Assignment rows and nothing else.
                $SafeId = $Key -replace '[/\\#?]', '_'
                $Prefix = "SharePointPermissions-${SafeId}_"
                $PrefixEsc = $Prefix -replace "'", "''"
                $Filter = "PartitionKey eq '$PartEsc' and RowKey ge '$PrefixEsc' and RowKey lt '${PrefixEsc}~'"
                $PriorRows = try { @(Get-CIPPAzDataTableEntity @Table -Filter $Filter) } catch { @() }
                foreach ($Row in $PriorRows) {
                    if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
                    $Parsed = try { $Row.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                    if (-not $Parsed) { continue }
                    if ($Parsed.rowType -eq 'Assignment') {
                        if (-not $PriorAssignmentsBySiteId.ContainsKey($Key)) {
                            $PriorAssignmentsBySiteId[$Key] = [System.Collections.Generic.List[object]]::new()
                        }
                        $PriorAssignmentsBySiteId[$Key].Add($Parsed)
                    } elseif ($Parsed.rowType -eq 'Site' -and -not $PriorSiteRowBySiteId.ContainsKey($Key)) {
                        $PriorSiteRowBySiteId[$Key] = $Parsed
                    }
                }
            }
        }

        # Stream rows into one Add-CIPPDbItem invocation and release each site's collected rows as
        # they are written, so the freshly-collected set is not held in memory beside the write.
        $Stats = @{ Assignments = 0 }
        & {
            foreach ($SiteResult in $SiteResults) {
                if ($SiteResult.SiteRow) { $SiteResult.SiteRow }

                if ($SiteResult.CollectionStatus -eq 'Skipped') {
                    $Key = [string]$SiteResult.SiteId
                    if ($PriorAssignmentsBySiteId.ContainsKey($Key)) {
                        foreach ($Row in $PriorAssignmentsBySiteId[$Key]) { $Stats.Assignments++; $Row }
                    }
                } else {
                    foreach ($Row in @($SiteResult.Rows)) {
                        if ($Row) {
                            if ($Row.rowType -eq 'Assignment') { $Stats.Assignments++ }
                            $Row
                        }
                    }
                }
                # Release this site's rows now the writer has them (best effort).
                try { $SiteResult.Rows = $null; $SiteResult.SiteRow = $null } catch {}
            }

            # Carry over every expected site no batch returned. A synthetic Skipped site row keeps the
            # site visible and flagged in the report; its prior assignment rows are restored.
            foreach ($Id in $MissingIds) {
                $Key = [string]$Id
                $Prior = $PriorSiteRowBySiteId[$Key]
                [PSCustomObject]@{
                    rowType                        = 'Site'
                    id                             = "${Key}_site"
                    siteId                         = $Key
                    siteName                       = $Prior.siteName
                    siteUrl                        = $Prior.siteUrl
                    collectionStatus               = 'Skipped'
                    collectionError                = 'Site was not returned by its collection batch this run; prior permission data retained.'
                    librariesScanned               = [int]($Prior.librariesScanned ?? 0)
                    librariesWithUniquePermissions = [int]($Prior.librariesWithUniquePermissions ?? 0)
                    collectedAt                    = $Prior.collectedAt
                }
                if ($PriorAssignmentsBySiteId.ContainsKey($Key)) {
                    foreach ($Row in $PriorAssignmentsBySiteId[$Key]) { $Stats.Assignments++; $Row }
                }
            }
        } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -AddCount

        $RestoredSites = $PriorAssignmentsBySiteId.Keys.Count
        $Sev = if ($MissingIds.Count -gt 0 -or $SkippedIds.Count -gt 0) { 'Warning' } else { 'Info' }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Stats.Assignments) SharePoint permission assignments for $TenantFilter : $CollectedCount of $ExpectedSiteCount sites collected, $($SkippedIds.Count) skipped, $($MissingIds.Count) missing (carried over), $RestoredSites restored from prior cache, from $(@($Item.Results).Count) batches" -sev $Sev
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store SharePoint permissions: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
