function Push-StoreSharePointPermissions {
    <#
    .SYNOPSIS
        Post-execution function that aggregates per-batch SharePoint permission rows and writes the cache.

    .DESCRIPTION
        Collects the Sites arrays returned by every Push-DBCacheSharePointPermissionsBatch activity,
        flattens their Site and Assignment rows into a single row set, and writes
        SharePointPermissions once via Add-CIPPDbItem.

        Completeness guard: if the number of site results does not match ExpectedSiteCount the
        function throws without writing. The cache is written in replace mode, so writing a partial
        set would silently discard every site the failed batches were responsible for.

        Merge-on-Skip: when a site returns Skipped, its rows are restored from the existing cache
        (matched on siteId) so a transient SPO failure does not erase permission data that was
        collected successfully on an earlier run. A Skipped site with no prior rows keeps just its
        Site row, which carries collectionStatus and the error - the report can then say the site
        could not be scanned rather than implying it has no permissions.

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

    try {
        $SiteResults = [System.Collections.Generic.List[object]]::new()
        foreach ($BatchResult in @($Item.Results)) {
            foreach ($SiteResult in @($BatchResult.Sites)) {
                if ($SiteResult) { $SiteResults.Add($SiteResult) }
            }
        }

        $ActualCount = $SiteResults.Count
        if ($ActualCount -ne $ExpectedSiteCount) {
            throw "SharePoint permissions completeness check failed for $TenantFilter : expected $ExpectedSiteCount site results, got $ActualCount"
        }

        # Restore rows for sites that could not be collected this run.
        $SkippedResults = @($SiteResults | Where-Object { $_.CollectionStatus -eq 'Skipped' })
        $MergedCount = 0
        $PriorRowsBySiteId = @{}
        if ($SkippedResults.Count -gt 0) {
            foreach ($Existing in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SharePointPermissions')) {
                if ($Existing.rowType -ne 'Assignment') { continue }
                $Key = [string]$Existing.siteId
                if (-not $Key) { continue }
                if (-not $PriorRowsBySiteId.ContainsKey($Key)) {
                    $PriorRowsBySiteId[$Key] = [System.Collections.Generic.List[object]]::new()
                }
                $PriorRowsBySiteId[$Key].Add($Existing)
            }
        }

        $AllRows = [System.Collections.Generic.List[object]]::new()
        foreach ($SiteResult in $SiteResults) {
            if ($SiteResult.SiteRow) { $AllRows.Add($SiteResult.SiteRow) }

            if ($SiteResult.CollectionStatus -eq 'Skipped') {
                $Key = [string]$SiteResult.SiteId
                if ($Key -and $PriorRowsBySiteId.ContainsKey($Key)) {
                    foreach ($Row in $PriorRowsBySiteId[$Key]) { $AllRows.Add($Row) }
                    $MergedCount++
                }
                continue
            }

            foreach ($Row in @($SiteResult.Rows)) {
                if ($Row) { $AllRows.Add($Row) }
            }
        }

        if ($SkippedResults.Count -gt 0) {
            $RemainingSkipped = $SkippedResults.Count - $MergedCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SharePoint permissions: $($SkippedResults.Count) of $ActualCount sites returned Skipped from collection; restored $MergedCount from prior cache; $RemainingSkipped have no permission rows" -sev Warning
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointPermissions' -Data @($AllRows) -AddCount

        $AssignmentCount = @($AllRows | Where-Object { $_.rowType -eq 'Assignment' }).Count
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $AssignmentCount SharePoint permission assignments across $ActualCount sites ($MergedCount merge-on-Skip) from $(@($Item.Results).Count) batches" -sev Info
        return

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store SharePoint permissions: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
