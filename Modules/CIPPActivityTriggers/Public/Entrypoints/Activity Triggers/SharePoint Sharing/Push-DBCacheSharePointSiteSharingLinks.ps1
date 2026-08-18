function Push-DBCacheSharePointSiteSharingLinks {
    <#
    .SYNOPSIS
        Scans SharePoint/OneDrive sharing links: site tasks fan out per drive, drive tasks scan
        one drive resumably.

    .DESCRIPTION
        One activity, two roles, discriminated by the payload:

        Site task ($Item.DriveId absent) - lists the site's document libraries, records how many
        drive tasks the site owns (drives-{site} row), and dispatches one drive task per drive
        through a child orchestration. Sites whose drives cannot be listed (locked/blocked sites,
        throttling) complete immediately as failed. The Preservation Hold Library is skipped by
        URL segment: it is a hidden system library that cannot carry sharing links and is often
        by far the largest drive on the site.

        Drive task ($Item.DriveId present) - scans one drive for shared items and writes
        sharing-link rows to the reporting DB page by page. Three scan modes:

          Principal   - full scan of a non-personal site's drive. Enumerates the backing list
                        with the hidden PrincipalCount field (999 rows per request); only items
                        whose principal count differs from the drive's inherited baseline have
                        extra role assignments (sharing links, direct grants), and only those get
                        a batched driveItem + permissions read. On group-connected team sites the
                        delta 'shared' facet is true for EVERY item (group access), so the classic
                        path costs one permission read per item; this path replaces that with
                        items/999 list pages + a permission read per actually-shared item.
                        The drive's deltaLink is captured afterwards via delta?token=latest so the
                        next scan runs incrementally.
          Full        - classic delta walk reading permissions for every shared-facet item. Used
                        for personal sites (OneDrive only flags genuinely shared items) and for
                        ForceFullSync, where it serves as the ground-truth deep scan.
          Incremental - delta from the stored token; only changed items are processed. Changed
                        items' existing rows are tombstoned and re-added from a fresh permission
                        read.

        Timebox - a drive task that exceeds CIPP_SHARINGLINKS_TIMEBOX_SECONDS (default 900)
        checkpoints and re-dispatches itself instead of running into the platform kill limit
        (Worker:BgTimeoutSeconds, default 1200): the runtime marks a timed-out task Failed
        without retry, so the task must yield before that. The checkpoint written after every
        persisted page means a re-dispatched task loses at most one page.

        Completion is tracked with insert-only marker rows (first writer wins), never counters:
        a scan-row counter was abandoned because concurrent decrements lost ETag races, and the
        companion failed-site list overflowed Azure Table's 64KB property cap at ~315 SharePoint
        composite site ids, silently losing decrements and leaving scans uncompletable.

        CippSharingLinksState rows (PartitionKey = tenant):
          scan                      scan identity: ScanId, TotalSites, FullSweep, StartedUtc
          drives-{site}             site's dispatched drive-task count for this scan
          ddone-{site}~{drive}      drive task completion marker (idempotent insert)
          done-{site}               site completion marker; Failed=true means the SITE failed
                                    (drives could not be listed) - drive-level failures instead
                                    keep their delta-state row current, which by itself protects
                                    their cached rows from finalisation pruning
          final                     finalisation claim marker (one finaliser per scan)
          chk-{site}~{drive}        drive task resume position, ScanId-gated
          delta-{drive}             per-drive delta token + last-scan bookkeeping

        The activity that completes the tenant's last pending site claims the 'final' marker and
        runs Push-StoreSharePointSharingLinks inline.

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
    # Re-dispatch budget: stay under the platform kill limit with room to finish the current
    # page - Craft kills background tasks at Worker:BgTimeoutSeconds (1200s), the Functions
    # consumption plan at 10 minutes.
    $TimeboxSeconds = if ($env:CIPPNG -eq 'true') { 1100 } else { 540 }
    if ($env:CIPP_SHARINGLINKS_TIMEBOX_SECONDS -match '^\d+$') { $TimeboxSeconds = [Math]::Max(1, [int]$env:CIPP_SHARINGLINKS_TIMEBOX_SECONDS) }

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

    # Converts one item's permission array into report rows. Shared by every scan mode; the only
    # difference between modes is where the permissions came from.
    function ConvertTo-CIPPSharingRow {
        param($Permissions, $DriveItem, $Drive, $Site, $InternalDomains, $RowsOut)
        foreach ($Permission in @($Permissions)) {
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

    # Fetch permissions for a buffer of shared delta items and append their rows to $RowsOut.
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
            ConvertTo-CIPPSharingRow -Permissions @($Response.body.value) -DriveItem $DriveItem -Drive $Drive -Site $Site -InternalDomains $InternalDomains -RowsOut $RowsOut
        }
    }

    # --- scan-state plumbing --------------------------------------------------------------------
    # These read the surrounding activity's variables directly; they exist to keep the call sites
    # readable, not to be reused.
    $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SiteKeySegment = ConvertTo-CIPPSharingLinksKeySegment -Value $SiteId

    function Get-ScanRow {
        Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
    }

    # Insert-only marker write. Returns $true when THIS caller created the marker for the current
    # scan - the idempotency primitive completion tracking is built on. A leftover marker from a
    # superseded scan that slipped past the parent's cleanup is taken over and counts as created.
    function Add-ScanMarker {
        param([string]$RowKey, [hashtable]$Extra = @{})
        $Marker = @{ PartitionKey = $TenantFilter; RowKey = $RowKey; ScanId = $ScanId } + $Extra
        try {
            Add-CIPPAzDataTableEntity @StateTable -Entity $Marker -ErrorAction Stop
            return $true
        } catch {
            $Existing = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String)'"
            if ($Existing -and [string]$Existing.ScanId -eq $ScanId) { return $false }
            Add-CIPPAzDataTableEntity @StateTable -Entity $Marker -Force
            return $true
        }
    }

    function Get-ScanMarkers {
        param([string]$Prefix)
        @(Get-CIPPAzDataTableEntity @StateTable -Filter ("PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}~~'" -f $SafeTenant, $Prefix) -Property @('PartitionKey', 'RowKey', 'ScanId', 'Failed')) |
            Where-Object { [string]$_.ScanId -eq $ScanId }
    }

    # Marks this site finished and runs finalisation if it was the last pending one. Idempotent:
    # the site marker is an insert (first writer wins), so duplicate dispatches count a site once;
    # the 'final' marker guarantees exactly one finaliser per scan. No counters anywhere - the
    # set of markers IS the completion state, so nothing can be lost to write conflicts.
    function Complete-Site {
        param([switch]$Failed)
        # A task from a scan that has since been superseded must not write markers - the current
        # scan owns them.
        $CurrentScan = Get-ScanRow
        if (-not $CurrentScan -or [string]$CurrentScan.ScanId -ne $ScanId) { return }

        $Created = Add-ScanMarker -RowKey "done-$SiteKeySegment" -Extra @{
            Failed       = [bool]$Failed
            CompletedUtc = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        }
        if (-not $Created) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: duplicate completion of '$SiteUrl' suppressed (scan $ScanId)" -sev Debug
            return
        }

        $DoneCount = @(Get-ScanMarkers -Prefix 'done-').Count
        if ($DoneCount -lt [int]$CurrentScan.TotalSites) { return }

        # Last site out claims finalisation; a concurrent completer that lost the claim skips.
        if (Add-ScanMarker -RowKey 'final') {
            Push-StoreSharePointSharingLinks -TenantFilter $TenantFilter -ScanId $ScanId
        }
    }

    # A task from a superseded scan has nothing valid to do; a fresh scan owns the state rows.
    $Scan = Get-ScanRow
    if (-not $Scan -or [string]$Scan.ScanId -ne $ScanId) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: skipping '$SiteUrl' - scan $ScanId superseded" -sev Debug
        return @()
    }

    $SiteContext = [PSCustomObject]@{
        SiteId         = $SiteId
        SiteName       = $SiteName
        SiteUrl        = $SiteUrl
        IsPersonalSite = $IsPersonalSite
    }

    # ================================ SITE TASK: fan out per drive ==============================
    if (-not $Item.DriveId) {
        try {
            $Drives = @()
            try {
                $Drives = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/drives?`$select=id,name,driveType,webUrl" -tenantid $TenantFilter -asapp $true)
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not list drives for '$SiteUrl': $($_.Exception.Message)" -sev Warning
                Complete-Site -Failed
                return @()
            }

            # The Preservation Hold Library holds retained copies users cannot share from; it is
            # frequently the biggest drive on the site and pure cost. Matched on the URL segment
            # because the display name is localised.
            $Drives = @($Drives | Where-Object { $_.id -and [string]$_.webUrl -notmatch '/PreservationHoldLibrary/?$' })

            if ($Drives.Count -eq 0) {
                Complete-Site
                return @()
            }

            # Record the drive-task total BEFORE dispatching: a drive task finishing first must
            # be able to see how many siblings it has.
            Add-CIPPAzDataTableEntity @StateTable -Entity @{
                PartitionKey = $TenantFilter
                RowKey       = "drives-$SiteKeySegment"
                ScanId       = $ScanId
                DriveCount   = [int]$Drives.Count
            } -Force

            $Batch = foreach ($Drive in $Drives) {
                [PSCustomObject]@{
                    FunctionName    = 'DBCacheSharePointSiteSharingLinks'
                    TenantFilter    = $TenantFilter
                    SiteId          = $SiteId
                    SiteName        = $SiteName
                    SiteUrl         = $SiteUrl
                    IsPersonalSite  = $IsPersonalSite
                    InternalDomains = @($InternalDomains)
                    ScanId          = $ScanId
                    DriveId         = [string]$Drive.id
                    DriveName       = [string]$Drive.name
                    ForceFull       = $ForceFull
                    QueueId         = $Item.QueueId
                    QueueName       = "Sharing Links - $($Drive.name) - $SiteUrl"
                }
            }
            if ($Item.QueueId) {
                try {
                    Update-CippQueueEntry -RowKey $Item.QueueId -TotalTasks $Drives.Count -IncrementTotalTasks
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not update queue $($Item.QueueId) with drive tasks: $($_.Exception.Message)" -sev Debug
                }
            }
            $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                    Batch            = @($Batch)
                    OrchestratorName = "SharingLinksDrives_$($TenantFilter)_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
                    SkipLog          = $true
                })
            return @()
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed dispatching drives for '$SiteUrl': $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
            Complete-Site -Failed
            return @()
        }
    }

    # ================================ DRIVE TASK: scan one drive ================================
    $Drive = [PSCustomObject]@{ id = [string]$Item.DriveId; name = [string]$Item.DriveName }
    $DriveKeySegment = ConvertTo-CIPPSharingLinksKeySegment -Value "$($Drive.id)"
    $CheckpointRowKey = "chk-$SiteKeySegment~$DriveKeySegment"
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    function Get-DriveCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if (-not $Row -or [string]$Row.ScanId -ne $ScanId) { return $null }
        try { ($Row.StateJson | ConvertFrom-Json -ErrorAction Stop) } catch { $null }
    }

    function Save-DriveCheckpoint {
        param($State)
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $CheckpointRowKey
            ScanId       = $ScanId
            StateJson    = [string]($State | ConvertTo-Json -Depth 10 -Compress)
        } -Force
    }

    function Remove-DriveCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if ($Row) { Remove-CIPPAzDataTableEntity @StateTable -Entity $Row -Force }
    }

    # Records the drive's scan outcome: delta token and which scan last saw it. Called on success
    # AND failure - a current LastScanId is what protects a failed drive's cached rows from
    # finalisation pruning. An empty DeltaLink forces the next scan to run full.
    function Set-DriveState {
        param([AllowEmptyString()][string]$DeltaLink = '', [switch]$FullScan)
        $NowUtc = [string]([DateTimeOffset]::UtcNow.ToString('o'))
        $Existing = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id
        $LastFullScanUtc = if ($FullScan) { $NowUtc } else { [string]($Existing.LastFullScanUtc ?? '') }
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey    = $TenantFilter
            RowKey          = "delta-$DriveKeySegment"
            DriveId         = [string]$Drive.id
            SiteId          = $SiteId
            DeltaLink       = [string]$DeltaLink
            LastScanId      = $ScanId
            LastScanUtc     = $NowUtc
            LastFullScanUtc = $LastFullScanUtc
        } -Force
    }

    # Marks this drive's task complete; when it is the site's last one, completes the site.
    function Complete-Drive {
        if (-not (Add-ScanMarker -RowKey "ddone-$SiteKeySegment~$DriveKeySegment")) { return }
        $DrivesRow = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'drives-$SiteKeySegment'"
        if (-not $DrivesRow -or [string]$DrivesRow.ScanId -ne $ScanId) { return }
        $DoneDrives = @(Get-ScanMarkers -Prefix "ddone-$SiteKeySegment~").Count
        if ($DoneDrives -ge [int]$DrivesRow.DriveCount) { Complete-Site }
    }

    # Checkpoints the position, re-dispatches this drive task and returns $true when the timebox
    # is spent. The platform kills tasks at Worker:BgTimeoutSeconds WITHOUT retrying them, so a
    # long drive must yield on its own; the fresh task resumes from the checkpoint.
    function Invoke-TimeboxRequeue {
        param($State)
        if ($Stopwatch.Elapsed.TotalSeconds -lt $TimeboxSeconds) { return $false }
        Save-DriveCheckpoint -State $State
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: timebox reached on drive '$($Drive.name)' ($SiteUrl); requeueing to resume" -sev Debug
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($Item)
                OrchestratorName = "SharingLinksResume_$($TenantFilter)_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
                SkipLog          = $true
            })
        return $true
    }

    $DeltaSelect = 'id,name,webUrl,folder,shared,deleted,size,lastModifiedDateTime'
    $FullDeltaUri = "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?`$select=$DeltaSelect&`$top=999"

    try {
        # Where does this drive start: checkpoint > stored delta token > full scan. Full scans of
        # non-personal sites use the PrincipalCount path unless this is a forced ground-truth
        # sync; OneDrive keeps the classic path because its shared facet is already selective.
        $Checkpoint = Get-DriveCheckpoint
        $Mode = if ($IsPersonalSite -or $ForceFull) { 'Full' } else { 'Principal' }
        $Uri = $null
        $Baseline = $null
        if ($Checkpoint -and $Checkpoint.CurrentUri) {
            $Mode = [string]$Checkpoint.CurrentMode
            $Uri = [string]$Checkpoint.CurrentUri
            $Baseline = $Checkpoint.Baseline
        } elseif (-not $ForceFull) {
            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id
            $LastFull = $(try { [DateTimeOffset]::Parse([string]$DriveState.LastFullScanUtc) } catch { [DateTimeOffset]::MinValue })
            if ($DriveState.DeltaLink -and $LastFull -gt [DateTimeOffset]::UtcNow.AddDays(-$FullScanDays)) {
                $Mode = 'Incremental'
                $Uri = [string]$DriveState.DeltaLink
            }
        }

        # ---------------- Principal mode: list enumeration filtered on PrincipalCount ----------
        if ($Mode -eq 'Principal') {
            try {
                if (-not $Uri) {
                    $List = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/list?`$select=id" -tenantid $TenantFilter -asapp $true
                    if (-not $List.id) { throw 'drive has no backing list' }
                    # Baseline = the number of principals an item inherits when nothing was ever
                    # shared on it. The drive root's permission objects are exactly that set.
                    $RootPermissions = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/permissions?`$select=id" -tenantid $TenantFilter -asapp $true)
                    $Baseline = [int]$RootPermissions.Count
                    $Uri = "https://graph.microsoft.com/beta/sites/$SiteId/lists/$($List.id)/items?`$top=999&`$select=id&`$expand=fields(`$select=PrincipalCount)"
                }

                $DroppedReads = 0
                while ($Uri) {
                    $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction

                    # An item whose principal count deviates from the inherited baseline carries
                    # extra (or unusual) role assignments; the permission read is the ground truth
                    # that filters inherited-only false positives back out.
                    $FlaggedIds = [System.Collections.Generic.List[string]]::new()
                    foreach ($ListItem in @($Page.value)) {
                        if ([int]$ListItem.fields.PrincipalCount -ne $Baseline -and $ListItem.id) { $FlaggedIds.Add([string]$ListItem.id) }
                    }

                    $PageRows = [System.Collections.Generic.List[object]]::new()
                    if ($FlaggedIds.Count -gt 0) {
                        $RequestId = 0
                        $ItemRequests = foreach ($FlaggedId in $FlaggedIds) {
                            @{
                                id     = "$RequestId"
                                method = 'GET'
                                url    = "sites/$SiteId/lists/$($List.id)/items/$FlaggedId/driveItem?`$select=id,name,webUrl,folder,size,lastModifiedDateTime&`$expand=permissions"
                            }
                            $RequestId++
                        }
                        $ItemResponses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($ItemRequests) -asapp $true
                        foreach ($Response in $ItemResponses) {
                            if ($Response.status -and $Response.status -ne 200) { $DroppedReads++; continue }
                            ConvertTo-CIPPSharingRow -Permissions @($Response.body.permissions) -DriveItem $Response.body -Drive $Drive -Site $SiteContext -InternalDomains $InternalDomains -RowsOut $PageRows
                        }
                    }
                    if ($PageRows.Count -gt 0) {
                        Add-CIPPDbItem -TenantFilter $TenantFilter -Type $CacheType -Data @($PageRows) -Append -RunId $ScanId
                    }

                    $Uri = [string]$Page.'@odata.nextLink'
                    if ($Uri) {
                        $State = @{ CurrentUri = $Uri; CurrentMode = 'Principal'; Baseline = $Baseline }
                        Save-DriveCheckpoint -State $State
                        if (Invoke-TimeboxRequeue -State $State) { return @() }
                    }
                }

                if ($DroppedReads -gt 0) {
                    # Throttled/failed batch responses mean some shared items were not rewritten
                    # this scan. Pruning now would delete their still-valid rows, so keep
                    # everything and force the next scan to run this drive full again.
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: $DroppedReads permission reads dropped on drive '$($Drive.name)' ($SiteUrl); keeping existing rows and deferring the sweep to the next full scan" -sev Warning
                    Set-DriveState -DeltaLink ''
                } else {
                    # Everything currently shared was rewritten with this scan's id; the rest is
                    # stale by definition.
                    $null = Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-${DriveKeySegment}_" -ExceptRunId $ScanId

                    # Capture the delta position without walking the drive, so the next scan of
                    # this drive runs incrementally off the classic path.
                    $DeltaLink = ''
                    try {
                        $TokenPage = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?token=latest&`$select=id" -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction
                        $DeltaLink = [string]$TokenPage.'@odata.deltaLink'
                    } catch {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not capture delta token for drive '$($Drive.name)' on '$SiteUrl': $($_.Exception.Message)" -sev Debug
                    }
                    Set-DriveState -DeltaLink $DeltaLink -FullScan
                }
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning drive '$($Drive.name)' on '$SiteUrl': $($_.Exception.Message)" -sev Warning
                # A current LastScanId with an empty token both protects this drive's cached
                # rows from pruning and forces the next scan to run full.
                Set-DriveState -DeltaLink ''
            }
            Remove-DriveCheckpoint
            Complete-Drive
            return @()
        }

        # ---------------- Full / Incremental: classic delta walk -------------------------------
        if (-not $Uri) { $Uri = $FullDeltaUri }

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
                $State = @{ CurrentUri = $Uri; CurrentMode = $Mode }
                Save-DriveCheckpoint -State $State
                if (Invoke-TimeboxRequeue -State $State) { return @() }
            }
        }

        if ($DriveFailed) {
            # An empty token in Full mode forces the next scan to start over, while a
            # preserved token in Incremental mode simply retries the same delta next scan.
            $KeepToken = if ($Mode -eq 'Incremental') {
                [string](Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id).DeltaLink
            } else { '' }
            Set-DriveState -DeltaLink $KeepToken
        } else {
            if ($Mode -eq 'Full') {
                # The scan rewrote every shared item's rows with this scan's id; anything left
                # under the drive's prefix without it is a link that no longer exists.
                $null = Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "$CacheType-${DriveKeySegment}_" -ExceptRunId $ScanId
            }
            Set-DriveState -DeltaLink ($DeltaLink ?? '') -FullScan:($Mode -eq 'Full')
        }

        Remove-DriveCheckpoint
        Complete-Drive
        return @()

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning drive '$($Drive.name)' on '$SiteUrl': $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        Set-DriveState -DeltaLink ''
        Remove-DriveCheckpoint
        Complete-Drive
        return @()
    }
}
