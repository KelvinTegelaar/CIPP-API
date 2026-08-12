function Push-DBCacheSharePointSiteSharingLinks {
    <#
    .SYNOPSIS
        Scans a single SharePoint/OneDrive site for sharing links, resumably.

    .DESCRIPTION
        Processes one site (fanned out by Set-CIPPDBCacheSharePointSharingLinks). Enumerates the
        site's drives and scans each for shared items, writing sharing-link rows straight to the
        reporting DB page by page. The activity runs to completion - there is deliberately no
        internal time budget or self-requeue; bounding runtime is the platform's job, not the
        scan's.

        What makes that safe on sites of any size:

        Checkpointing — after every page whose rows have been persisted, the drive's next delta
        page URL is saved (along with which drives already finished). A run killed by a timeout,
        recycle or crash loses at most one page: re-dispatching the same task resumes exactly
        where the dead run stopped. That re-dispatch is the retry mechanism's contract - any
        task-level retry (runtime or scheduler) can fire the same payload again at any time.

        Idempotent completion — a retried task can race a still-alive original, so counting a
        site against the scan's pending counter is guarded by a first-writer-wins marker row.
        However often a site's task is dispatched, it decrements the counter exactly once;
        without that, a duplicate would drive the counter to zero early and finalisation would
        prune rows of sites still mid-scan.

        Delta persistence — when a drive completes, its Graph deltaLink is stored. The next scan
        replays only items changed since (tombstoning each changed item's old rows and re-reading
        its permissions) instead of enumerating the whole drive. A drive falls back to a full scan
        when its token is rejected (resyncRequired), when its last full scan is older than
        CIPP_SHARINGLINKS_FULLSCAN_DAYS (default 14, bounding drift from any change delta misses),
        or when the sync was started with ForceFullSync.

        Scan progress lives in the CippSharingLinksState table (see the fan-out parent for the
        row layout). The single-caller state operations - checkpoint CRUD, drive-state writes and
        the completion counter - are nested functions here rather than module functions, so only
        genuinely shared helpers exist as files. The activity that completes the tenant's last
        pending site runs Push-StoreSharePointSharingLinks to prune rows of vanished drives and
        refresh the count.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = Resolve-CIPPSharingLinksTenantFilter -TenantFilter $Item.TenantFilter
    $SiteId = $Item.SiteId
    $SiteName = $Item.SiteName
    $SiteUrl = $Item.SiteUrl
    $IsPersonalSite = [bool]$Item.IsPersonalSite
    $ScanId = [string]$Item.ScanId
    $ForceFull = [bool]$Item.ForceFull
    $CacheType = 'SharePointSharingLinks'

    $FullScanDays = 14
    if ($env:CIPP_SHARINGLINKS_FULLSCAN_DAYS -match '^\d+$') { $FullScanDays = [Math]::Max(1, [int]$env:CIPP_SHARINGLINKS_FULLSCAN_DAYS) }

    # Verified domains passed from the parent; used to tell internal from external recipients.
    $InternalDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Domain in @($Item.InternalDomains)) { if ($Domain) { [void]$InternalDomains.Add([string]$Domain) } }

    # Returns $true when an identity (link recipient or direct grant) is external to the tenant.
    function Test-CIPPExternalIdentity {
        param($Identity, $InternalDomains)
        $LoginName = [string]($Identity.siteUser.loginName ?? $Identity.user.loginName ?? '')
        if ($LoginName -match '#ext#' -or $LoginName -match 'urn%3aspo%3aguest' -or $LoginName -match 'urn:spo:guest') { return $true }
        $Email = [string]($Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? '')
        if ($Email -match '#EXT#') { return $true }
        if ($Email -and $Email.Contains('@') -and $InternalDomains.Count -gt 0) {
            return -not $InternalDomains.Contains($Email.Split('@')[-1])
        }
        return $false
    }

    # Friendly display value for an identity, preferring email over display name.
    function Get-CIPPIdentityLabel {
        param($Identity)
        $Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? $Identity.user.displayName ?? $Identity.siteUser.displayName ?? $Identity.group.email ?? $Identity.group.displayName ?? $Identity.siteGroup.displayName
    }

    # Fetch permissions for a buffer of shared items and append their sharing-link rows to $RowsOut.
    function Add-CIPPSharingRows {
        param($Buffer, $Drive, $Site, $InternalDomains, $TenantFilter, $RowsOut)

        if (@($Buffer).Count -eq 0) { return }

        $ItemByRequestId = @{}
        $RequestId = 0
        $PermissionRequests = foreach ($SharedItem in $Buffer) {
            $ItemByRequestId["$RequestId"] = $SharedItem
            @{
                id     = "$RequestId"
                method = 'GET'
                url    = "drives/$($Drive.id)/items/$($SharedItem.id)/permissions"
            }
            $RequestId++
        }

        $PermissionResponses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($PermissionRequests) -asapp $true
        foreach ($Response in $PermissionResponses) {
            if ($Response.status -and $Response.status -ne 200) { continue }
            $DriveItem = $ItemByRequestId["$($Response.id)"]

            foreach ($Permission in @($Response.body.value)) {
                # Only permissions set on the item itself; inherited ones are reported on their parent.
                if ($Permission.inheritedFrom) { continue }

                if ($Permission.link) {
                    $Recipients = @($Permission.grantedToIdentitiesV2 ?? $Permission.grantedToIdentities)
                    $LinkScope = $Permission.link.scope ?? 'users'
                    $Classification = switch ($LinkScope) {
                        'anonymous' { 'Anonymous' }
                        'organization' { 'Internal' }
                        'existingAccess' { 'Internal' }
                        default {
                            $HasExternal = $false
                            foreach ($Recipient in $Recipients) {
                                if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
                            }
                            if ($HasExternal) { 'External' } else { 'Internal' }
                        }
                    }
                    $LinkType = $Permission.link.type ?? 'link'
                    $LinkUrl = $Permission.link.webUrl
                } else {
                    # Direct grant (no sharing link): only report grants to external users.
                    $Recipients = @($Permission.grantedToV2 ?? $Permission.grantedTo)
                    if ($Permission.roles -contains 'owner') { continue }
                    $HasExternal = $false
                    foreach ($Recipient in $Recipients) {
                        if (Test-CIPPExternalIdentity -Identity $Recipient -InternalDomains $InternalDomains) { $HasExternal = $true; break }
                    }
                    if (-not $HasExternal) { continue }
                    $Classification = 'External'
                    $LinkScope = 'direct'
                    $LinkType = 'directGrant'
                    $LinkUrl = $null
                }

                $SharedWith = @($Recipients | ForEach-Object { Get-CIPPIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)

                $RowsOut.Add([PSCustomObject]@{
                        id                   = "$($Drive.id)_$($DriveItem.id)_$($Permission.id)"
                        siteId               = $Site.SiteId
                        siteName             = $Site.SiteName
                        siteUrl              = $Site.SiteUrl
                        workload             = if ($Site.IsPersonalSite) { 'OneDrive' } else { 'SharePoint' }
                        driveId              = $Drive.id
                        driveName            = $Drive.name
                        itemId               = $DriveItem.id
                        fileName             = $DriveItem.name
                        itemUrl              = $DriveItem.webUrl
                        itemType             = if ($DriveItem.folder) { 'Folder' } else { 'File' }
                        size                 = $DriveItem.size
                        lastModifiedDateTime = $DriveItem.lastModifiedDateTime
                        permissionId         = $Permission.id
                        linkType             = $LinkType
                        linkScope            = $LinkScope
                        classification       = $Classification
                        roles                = @($Permission.roles)
                        sharedWith           = $SharedWith
                        linkUrl              = $LinkUrl
                        hasPassword          = $Permission.hasPassword ?? $false
                        expirationDateTime   = $Permission.expirationDateTime
                    })
            }
        }
    }

    # --- scan-state plumbing --------------------------------------------------------------------
    # These read the surrounding activity's variables ($StateTable, $SafeTenant, $ScanId, ...)
    # directly; they exist to keep the call sites in the scan loop readable, not to be reused.
    $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SiteKeySegment = ConvertTo-CIPPSharingLinksKeySegment -Value $SiteId
    $CheckpointRowKey = "chk-$SiteKeySegment"

    function Get-ScanRow {
        Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
    }

    function Get-SiteCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if (-not $Row -or [string]$Row.ScanId -ne $ScanId) { return $null }
        try { ($Row.StateJson | ConvertFrom-Json -ErrorAction Stop) } catch { $null }
    }

    function Save-SiteCheckpoint {
        param($State)
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $CheckpointRowKey
            ScanId       = $ScanId
            StateJson    = [string]($State | ConvertTo-Json -Depth 10 -Compress)
        } -Force
    }

    function Remove-SiteCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if ($Row) { Remove-CIPPAzDataTableEntity @StateTable -Entity $Row -Force }
    }

    # Records a drive's scan outcome: delta token and which scan last saw it. Called on success
    # AND failure - LastScanId is how finalisation tells a failed drive (keep its rows one more
    # cycle) from a deleted one (prune). An empty DeltaLink forces the next scan to run full.
    function Set-DriveState {
        param([string]$DriveId, [AllowEmptyString()][string]$DeltaLink = '', [switch]$FullScan)
        $NowUtc = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        $Existing = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $DriveId
        $LastFullScanUtc = if ($FullScan) { $NowUtc } else { [string]($Existing.LastFullScanUtc ?? '') }
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey    = $TenantFilter
            RowKey          = "delta-$(ConvertTo-CIPPSharingLinksKeySegment -Value $DriveId)"
            DriveId         = $DriveId
            SiteId          = $SiteId
            DeltaLink       = [string]$DeltaLink
            LastScanId      = $ScanId
            LastScanUtc     = $NowUtc
            LastFullScanUtc = $LastFullScanUtc
        } -Force
    }

    # Marks this site finished (successfully or failed) and runs finalisation if it was the last
    # pending one. Idempotent: the marker row is an insert (first writer wins), so however many
    # times a retry mechanism dispatches this site, the counter is decremented exactly once - a
    # duplicate decrement would reach zero early and finalisation would prune rows of sites that
    # are still scanning. The decrement itself is ETag-conditional so two DIFFERENT sites
    # finishing at once cannot both write the same counter value; the losing writer rereads and
    # retries. A superseded scan or a persistent write conflict must never finalise.
    function Complete-Site {
        param([switch]$Failed)
        # A task from a scan that has since been superseded must not write markers or touch
        # counters - the current scan owns them.
        $CurrentScan = Get-ScanRow
        if (-not $CurrentScan -or [string]$CurrentScan.ScanId -ne $ScanId) { return }

        $Marker = @{
            PartitionKey = $TenantFilter
            RowKey       = "done-$SiteKeySegment"
            ScanId       = $ScanId
            Failed       = [bool]$Failed
            CompletedUtc = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        }
        try {
            # Insert, not upsert: failing on an existing marker IS the duplicate detection.
            Add-CIPPAzDataTableEntity @StateTable -Entity $Marker -ErrorAction Stop
        } catch {
            # Conflict: either this site was already counted against the current scan (a retry
            # racing the original - suppress), or the marker is a leftover of a superseded scan
            # that slipped past the parent's cleanup - take it over and count normally.
            $Existing = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'done-$SiteKeySegment'"
            if ($Existing -and [string]$Existing.ScanId -eq $ScanId) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: duplicate completion of '$SiteUrl' suppressed (scan $ScanId)" -sev Debug
                return
            }
            Add-CIPPAzDataTableEntity @StateTable -Entity $Marker -Force
        }
        $Pending = $null
        for ($Attempt = 0; $Attempt -lt 10; $Attempt++) {
            $ScanRow = Get-ScanRow
            if (-not $ScanRow -or [string]$ScanRow.ScanId -ne $ScanId) { return }
            $ScanRow.PendingSites = [int]$ScanRow.PendingSites - 1
            if ($Failed) {
                $FailedList = @()
                try { $FailedList = @($ScanRow.FailedSites | ConvertFrom-Json -ErrorAction Stop) } catch {}
                # Capped so the property can never outgrow a table column; the per-site log entry
                # carries the detail, and finalisation only needs membership.
                if ($FailedList.Count -lt 500) { $FailedList = @($FailedList) + $SiteId }
                $ScanRow.FailedSites = [string](ConvertTo-Json @($FailedList) -Compress)
            }
            try {
                # -ErrorAction Stop is load-bearing: the cmdlet reports an ETag conflict (412)
                # as a NON-terminating error, which would sail past this catch, skip the retry
                # and silently lose the decrement - leaving the counter stuck above zero and
                # finalisation never running.
                $null = Update-AzDataTableEntity @StateTable -Entity $ScanRow -ErrorAction Stop
                $Pending = [int]$ScanRow.PendingSites
                break
            } catch {
                Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 250)
            }
        }
        if ($null -eq $Pending) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not update scan counter for scan $ScanId after 10 attempts; finalisation may not run this scan" -sev Warning
            return
        }
        if ($Pending -le 0) {
            Push-StoreSharePointSharingLinks -TenantFilter $TenantFilter -ScanId $ScanId
        }
    }

    # A task from a superseded scan has nothing valid to resume; a fresh scan owns the state
    # rows now. Exit without touching counters.
    $Scan = Get-ScanRow
    $ScanActive = $Scan -and [string]$Scan.ScanId -eq $ScanId
    if (-not $ScanActive) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: skipping '$SiteUrl' - scan $ScanId superseded" -sev Debug
        return @()
    }

    try {
        # 1) Drives (document libraries) for this one site.
        $Drives = @()
        try {
            $Drives = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/drives?`$select=id,name,driveType,webUrl" -tenantid $TenantFilter -asapp $true)
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not list drives for '$SiteUrl': $($_.Exception.Message)" -sev Warning
            Complete-Site -Failed
            return @()
        }

        $SiteContext = [PSCustomObject]@{
            SiteId         = $SiteId
            SiteName       = $SiteName
            SiteUrl        = $SiteUrl
            IsPersonalSite = $IsPersonalSite
        }

        # Resume position from an earlier (killed or retried) run of this site, if any.
        $Checkpoint = Get-SiteCheckpoint
        $CompletedDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Done in @($Checkpoint.CompletedDrives)) { if ($Done) { [void]$CompletedDrives.Add([string]$Done) } }

        $DeltaSelect = 'id,name,webUrl,folder,shared,deleted,size,lastModifiedDateTime'

        # 2) Scan each drive, page by page, persisting rows and checkpointing as we go.
        foreach ($Drive in $Drives) {
            if (-not $Drive.id) { continue }
            if ($CompletedDrives.Contains([string]$Drive.id)) { continue }

            $DriveKeySegment = ConvertTo-CIPPSharingLinksKeySegment -Value "$($Drive.id)"
            $FullDeltaUri = "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?`$select=$DeltaSelect&`$top=999"

            # Where does this drive start: mid-drive checkpoint > stored delta token > full scan.
            $Mode = 'Full'
            $Uri = $FullDeltaUri
            if ($Checkpoint -and [string]$Checkpoint.CurrentDriveId -eq [string]$Drive.id -and $Checkpoint.CurrentUri) {
                $Mode = [string]$Checkpoint.CurrentMode
                $Uri = [string]$Checkpoint.CurrentUri
            } elseif (-not $ForceFull) {
                $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id
                $LastFull = $(try { [DateTimeOffset]::Parse([string]$DriveState.LastFullScanUtc) } catch { [DateTimeOffset]::MinValue })
                if ($DriveState.DeltaLink -and $LastFull -gt [DateTimeOffset]::UtcNow.AddDays(-$FullScanDays)) {
                    $Mode = 'Incremental'
                    $Uri = [string]$DriveState.DeltaLink
                }
            }

            # Incremental scans tombstone every changed item's existing rows before re-adding the
            # ones it still carries. One keys-only read up front replaces a per-item query: the
            # itemId is recoverable from the RowKey because it sits between the known drive
            # prefix and the next '_' (SPO item ids never contain underscores).
            $ExistingRowsByItem = $null
            if ($Mode -eq 'Incremental') {
                $ExistingRowsByItem = @{}
                $DrivePrefix = "$CacheType-${DriveKeySegment}_"
                foreach ($Row in (Get-CIPPSharingLinksRowKeysByPrefix -TenantFilter $TenantFilter -Prefix $DrivePrefix)) {
                    if (-not $Row.RowKey) { continue }
                    $Suffix = ([string]$Row.RowKey).Substring($DrivePrefix.Length)
                    $ItemKey = $Suffix.Split('_')[0]
                    if (-not $ExistingRowsByItem.ContainsKey($ItemKey)) { $ExistingRowsByItem[$ItemKey] = [System.Collections.Generic.List[object]]::new() }
                    $ExistingRowsByItem[$ItemKey].Add($Row)
                }
            }

            $DeltaLink = $null
            $DriveFailed = $false
            while ($Uri) {
                try {
                    $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction
                } catch {
                    $ErrorMessage = $_.Exception.Message
                    if ($Mode -eq 'Incremental' -and $ErrorMessage -match 'resync|SyncStateNotFound|Gone|410') {
                        # Token invalidated server-side; the drive needs a fresh full enumeration.
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: delta token for drive '$($Drive.name)' on '$SiteUrl' expired; falling back to full scan" -sev Debug
                        $Mode = 'Full'
                        $Uri = $FullDeltaUri
                        $ExistingRowsByItem = $null
                        continue
                    }
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning drive '$($Drive.name)' on '$SiteUrl': $ErrorMessage" -sev Warning
                    $DriveFailed = $true
                    break
                }

                $Buffer = [System.Collections.Generic.List[object]]::new()
                $TombstoneRows = [System.Collections.Generic.List[object]]::new()
                foreach ($PageItem in @($Page.value)) {
                    if ($Mode -eq 'Incremental' -and $ExistingRowsByItem) {
                        # Every changed item invalidates whatever rows it had - deleted items,
                        # items no longer shared, and items whose link set changed all converge
                        # on: drop the old rows, re-add from the fresh permission read below.
                        $ItemKey = ConvertTo-CIPPSharingLinksKeySegment -Value "$($PageItem.id)"
                        if ($ExistingRowsByItem.ContainsKey($ItemKey)) {
                            foreach ($Row in $ExistingRowsByItem[$ItemKey]) { $TombstoneRows.Add($Row) }
                            $ExistingRowsByItem.Remove($ItemKey)
                        }
                    }
                    if ($PageItem.shared -and -not $PageItem.deleted) { $Buffer.Add($PageItem) }
                }

                # Rows for this page: permission lookups happen per page so the checkpoint below
                # never advances past work that has not been persisted.
                $PageRows = [System.Collections.Generic.List[object]]::new()
                Add-CIPPSharingRows -Buffer $Buffer -Drive $Drive -Site $SiteContext -InternalDomains $InternalDomains -TenantFilter $TenantFilter -RowsOut $PageRows

                if ($TombstoneRows.Count -gt 0) {
                    $Table = Get-CippTable -tablename 'CippReportingDB'
                    $null = Remove-CIPPAzDataTableEntity @Table -Entity $TombstoneRows.ToArray() -Force
                }
                if ($PageRows.Count -gt 0) {
                    Add-CIPPDbItem -TenantFilter $TenantFilter -Type $CacheType -Data @($PageRows) -Append -RunId $ScanId
                }

                if ($Page.'@odata.deltaLink') {
                    $DeltaLink = [string]$Page.'@odata.deltaLink'
                    $Uri = $null
                } else {
                    $Uri = [string]$Page.'@odata.nextLink'
                }

                # This page's rows are persisted, so the resume position may advance past it.
                if ($Uri) {
                    Save-SiteCheckpoint -State @{
                        CompletedDrives = @($CompletedDrives)
                        CurrentDriveId  = [string]$Drive.id
                        CurrentUri      = $Uri
                        CurrentMode     = $Mode
                    }
                }
            }

            if ($DriveFailed) {
                # An empty token in Full mode forces the next scan to start over, while a
                # preserved token in Incremental mode simply retries the same delta next scan.
                $KeepToken = if ($Mode -eq 'Incremental') {
                    [string](Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id).DeltaLink
                } else { '' }
                Set-DriveState -DriveId $Drive.id -DeltaLink $KeepToken
            } else {
                if ($Mode -eq 'Full') {
                    # The scan rewrote every shared item's rows with this scan's id; anything left
                    # under the drive's prefix without it is a link that no longer exists.
                    $null = Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-${DriveKeySegment}_" -ExceptRunId $ScanId
                }
                Set-DriveState -DriveId $Drive.id -DeltaLink ($DeltaLink ?? '') -FullScan:($Mode -eq 'Full')
            }

            [void]$CompletedDrives.Add([string]$Drive.id)
            $Checkpoint = $null
            # Advance the persisted position past the finished drive so a crash before the next
            # drive's first page cannot resume into a drive that already completed.
            Save-SiteCheckpoint -State @{
                CompletedDrives = @($CompletedDrives)
                CurrentDriveId  = ''
                CurrentUri      = ''
                CurrentMode     = ''
            }
        }

        # 3) Site complete.
        Remove-SiteCheckpoint
        Complete-Site
        return @()

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning site '$SiteUrl': $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Complete-Site -Failed
        return @()
    }
}
