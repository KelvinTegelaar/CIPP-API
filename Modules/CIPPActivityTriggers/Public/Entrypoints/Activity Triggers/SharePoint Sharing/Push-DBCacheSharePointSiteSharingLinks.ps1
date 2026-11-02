function Push-DBCacheSharePointSiteSharingLinks {
    <#
    .SYNOPSIS
        Scans SharePoint/OneDrive sharing links: site tasks fan out per drive, drive tasks scan
        one drive resumably.

    .DESCRIPTION
        One activity, two roles, discriminated by the payload:

        Site task ($Item.DriveId absent) - lists the site's document libraries and records them in
        the drives-{site} row; the site run's post-execution queues every site's drives as one
        capped run per tenant (Push-SharingLinksDispatchDrives). Sites whose drives cannot be
        listed (locked/blocked sites, throttling) complete immediately as failed. The Preservation
        Hold Library is skipped by URL segment: it is a hidden system library that cannot carry
        sharing links and is often by far the largest drive on the site. One SharePoint REST call per
        site finds each library's item count (for scan progress) and whether it holds its own
        permissions: an inheriting library's root
        only repeats the site's permissions, so its root is not read. Links cannot be set on a
        library root, so the root read exists only for direct grants on the library itself.

        Drive task ($Item.DriveId present) - scans one drive for shared items and writes
        sharing-link rows to the CippSharingLinks table page by page. Two scan modes:

          Full        - delta walk reading permissions for every shared-facet item. This is the
                        ground truth, deliberately: a PrincipalCount pre-filter was tried and
                        removed because paged list enumeration serves stale principal counts on
                        large busy lists, silently under-reporting shares. The delta is read with
                        Prefer: hierarchicalsharing, so only permission-hierarchy roots and
                        explicitly shared items carry the facet; without it every file on a
                        group-connected team site does, costing a permission read per file.
          Incremental - delta from the stored token; only changed items are processed. Changed
                        items' existing rows are tombstoned and re-added from a fresh permission
                        read. A drive runs full only without a token, when the token is rejected,
                        or when it holds fewer rows than its last scan recorded.

        An item can appear in a delta more than once; only its last occurrence counts, so rows
        written for an earlier occurrence in the same scan are tombstoned like stale ones.

        Redrive - a drive task that is killed at the platform limit or throttled out mid-scan
        leaves its drive without a completion marker. The drive run's post-execution queues every
        such drive again for as long as it keeps saving pages, and each resumes from the checkpoint
        written after every persisted page, so it loses at most one page. A drive that saved no
        page in a round stops for this scan (Stalled): it keeps its rows, stores its position on
        its delta row, and the next scan resumes from there - or rescans in full if the position is
        rejected. Rows carry the id of the scan that started their pass (PassId), so a full pass
        spanning several scans still sweeps only what it did not rewrite.

        Completion is tracked with insert-only marker rows (first writer wins), never counters:
        a scan-row counter was abandoned because concurrent decrements lost ETag races, and the
        companion failed-site list overflowed Azure Table's 64KB property cap at ~315 SharePoint
        composite site ids, silently losing decrements and leaving scans uncompletable.

        CippSharingLinksState rows (PartitionKey = tenant):
          scan                      scan identity: ScanId, TotalSites, FullSweep, StartedUtc
          drives-{site}             site's drives for this scan (count, ids, site details)
          ddone-{site}~{drive}      drive task completion marker (idempotent insert)
          done-{site}               site completion marker; Failed=true means the SITE failed
                                    (drives could not be listed) - drive-level failures instead
                                    keep their delta-state row current, which by itself protects
                                    their cached rows from finalisation pruning
          final                     finalisation claim marker (one finaliser per scan)
          chk-{site}~{drive}        drive task resume position, ScanId-gated
          delta-{drive}             per-drive delta token, row count, stored resume position +
                                    last-scan bookkeeping
          summary                   tenant link count and when the last scan finalised

        The activity that completes the tenant's last pending site claims the 'final' marker and
        runs Push-StoreSharePointSharingLinks inline.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = [string]$Item.TenantFilter
    $SiteId = $Item.SiteId
    $SiteName = $Item.SiteName
    $SiteUrl = $Item.SiteUrl
    $IsPersonalSite = [bool]$Item.IsPersonalSite
    $ScanId = [string]$Item.ScanId
    $ForceFull = [bool]$Item.ForceFull

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

            $Id = "$($Drive.id)_$($DriveItem.id)_$($Permission.id)"
            $RowsOut.Add(@{
                    PartitionKey         = $TenantFilter
                    RowKey               = ([string]$Id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')
                    ScanId               = $PassId
                    id                   = $Id
                    siteId               = [string]$Site.SiteId
                    siteName             = [string]$Site.SiteName
                    siteUrl              = [string]$Site.SiteUrl
                    workload             = if ($Site.IsPersonalSite) { 'OneDrive' } else { 'SharePoint' }
                    driveId              = [string]$Drive.id
                    driveName            = [string]$Drive.name
                    itemId               = [string]$DriveItem.id
                    fileName             = [string]$DriveItem.name
                    itemUrl              = [string]$DriveItem.webUrl
                    itemType             = if ($DriveItem.folder) { 'Folder' } else { 'File' }
                    size                 = [int64]($DriveItem.size ?? 0)
                    lastModifiedDateTime = if ($DriveItem.lastModifiedDateTime -is [datetime]) { $DriveItem.lastModifiedDateTime.ToUniversalTime().ToString('o') } else { [string]$DriveItem.lastModifiedDateTime }
                    permissionId         = [string]$Permission.id
                    linkType             = [string]$LinkType
                    linkScope            = [string]$LinkScope
                    classification       = [string]$Classification
                    roles                = [string](ConvertTo-Json -InputObject @($Permission.roles) -Compress)
                    sharedWith           = [string](ConvertTo-Json -InputObject @($SharedWith) -Compress)
                    linkUrl              = [string]$LinkUrl
                    hasPassword          = [bool]($Permission.hasPassword ?? $false)
                    expirationDateTime   = if ($Permission.expirationDateTime -is [datetime]) { $Permission.expirationDateTime.ToUniversalTime().ToString('o') } else { [string]$Permission.expirationDateTime }
                })
        }
    }

    # Fetch permissions for a buffer of shared delta items and append their rows to $RowsOut.
    # Failed batch responses are counted into $DropCounter: a full scan that lost reads must not
    # prune the unread items' still-valid rows afterwards.
    function Add-CIPPSharingRows {
        param($Buffer, $Drive, $Site, $InternalDomains, $TenantFilter, $RowsOut, [ref]$DropCounter)
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
            if ($Response.status -and $Response.status -ne 200) {
                if ($DropCounter) { $DropCounter.Value++ }
                continue
            }
            $DriveItem = $ItemByRequestId["$($Response.id)"]
            ConvertTo-CIPPSharingRow -Permissions @($Response.body.value) -DriveItem $DriveItem -Drive $Drive -Site $Site -InternalDomains $InternalDomains -RowsOut $RowsOut
        }
    }

    # --- scan-state plumbing --------------------------------------------------------------------
    # These read the surrounding activity's variables directly; they exist to keep the call sites
    # readable, not to be reused.
    $StateTable = Get-CippTable -tablename 'CippSharingLinksState'
    $LinksTable = Get-CippTable -tablename 'CippSharingLinks'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
    $SiteKeySegment = ([string]$SiteId -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')

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
                if ($_.Exception.Message -match 'Access to this site has been blocked') {
                    # A NoAccess-locked site (typically an offboarded user's OneDrive) blocks ALL
                    # content access, sharing-link redemption included - its links are dead while
                    # the lock stands. Complete un-failed WITHOUT scanning: finalisation then
                    # prunes the site's stale rows, and an unlock later triggers a fresh full
                    # scan that re-adds them.
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: skipping locked site '$SiteUrl' - access is blocked, so its sharing links are inactive" -sev Info
                    Complete-Site
                    return @()
                }
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

            # Library root path -> its list. A library this cannot place keeps its root read and has no item count.
            $Libraries = @{}
            if ($Item.SharePointScope) {
                try {
                    $Lists = @(New-GraphGetRequest -uri "$($SiteUrl.TrimEnd('/'))/_api/web/lists?`$select=ItemCount,HasUniqueRoleAssignments,RootFolder/ServerRelativeUrl&`$expand=RootFolder" -tenantid $TenantFilter -scope $Item.SharePointScope -extraHeaders @{ Accept = 'application/json;odata=nometadata' } -UseCertificate -AsApp $true)
                    foreach ($List in $Lists) {
                        if ($List.RootFolder.ServerRelativeUrl) { $Libraries[[string]$List.RootFolder.ServerRelativeUrl] = $List }
                    }
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not check library permissions on '$SiteUrl', reading every library root: $($_.Exception.Message)" -sev Debug
                }
            }

            # The dispatch post-execution builds every round's drive tasks from this row.
            Add-CIPPAzDataTableEntity @StateTable -Entity @{
                PartitionKey   = $TenantFilter
                RowKey         = "drives-$SiteKeySegment"
                ScanId         = $ScanId
                DriveCount     = [int]$Drives.Count
                SiteId         = [string]$SiteId
                SiteName       = [string]$SiteName
                SiteUrl        = [string]$SiteUrl
                IsPersonalSite = $IsPersonalSite
                DrivesJson     = [string](ConvertTo-Json -InputObject @($Drives | ForEach-Object {
                            $List = if ($_.webUrl) { $Libraries[[uri]::UnescapeDataString(([uri][string]$_.webUrl).AbsolutePath)] }
                            @{
                                id        = [string]$_.id
                                name      = [string]$_.name
                                readRoot  = $null -eq $List -or $List.HasUniqueRoleAssignments -ne $false
                                itemCount = [int64]($List.ItemCount ?? -1)
                            }
                        }) -Compress)
            } -Force

            if ($Item.QueueId) {
                try {
                    Update-CippQueueEntry -RowKey $Item.QueueId -TotalTasks $Drives.Count -IncrementTotalTasks
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not update queue $($Item.QueueId) with drive tasks: $($_.Exception.Message)" -sev Debug
                }
            }
            return @()
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed dispatching drives for '$SiteUrl': $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
            Complete-Site -Failed
            return @()
        }
    }

    # ================================ DRIVE TASK: scan one drive ================================
    $Drive = [PSCustomObject]@{ id = [string]$Item.DriveId; name = [string]$Item.DriveName }
    $ReadRoot = $Item.ReadRoot -ne $false
    $DriveKeySegment = ([string]$Drive.id -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')
    $CheckpointRowKey = "chk-$SiteKeySegment~$DriveKeySegment"

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

    # Records the drive's scan outcome: delta token, which scan last saw it and how many rows it
    # holds. Called on success AND failure - a current LastScanId is what protects a failed drive's
    # cached rows from finalisation pruning. An empty DeltaLink forces the next scan to run full.
    function Set-DriveState {
        param([AllowEmptyString()][string]$DeltaLink = '', [switch]$FullScan, $Resume)
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
            RootItemId      = [string]($RootItemId ?? $Existing.RootItemId ?? '')
            ResumeUri       = [string]$Resume.CurrentUri
            ResumeMode      = [string]$Resume.CurrentMode
            ResumePassId    = [string]$Resume.PassId
            ResumeItemsSeen = [int64]($Resume.ItemsSeen ?? 0)
            ResumeDropped   = [int]($Resume.DroppedReads ?? 0)
            RowCount        = @(Get-CIPPSharingLinksRowKeysByPrefix -TenantFilter $TenantFilter -Prefix "${DriveKeySegment}_").Count
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

    if ($Item.Stalled) {
        # No page saved since the last round: keep the rows and the position, and let the next scan resume.
        $Checkpoint = Get-DriveCheckpoint
        $Existing = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: drive '$($Drive.name)' ($SiteUrl) stopped making progress; keeping its rows and resuming next scan" -sev Warning
        Set-DriveState -DeltaLink ([string]$Existing.DeltaLink) -Resume $(if ($Checkpoint.CurrentUri) { $Checkpoint } else { $Existing | Where-Object { $_.ResumeUri } | ForEach-Object { @{ CurrentUri = $_.ResumeUri; CurrentMode = $_.ResumeMode; PassId = $_.ResumePassId; ItemsSeen = $_.ResumeItemsSeen; DroppedReads = $_.ResumeDropped } } })
        Remove-DriveCheckpoint
        Complete-Drive
        return @()
    }

    $DeltaSelect = 'id,name,webUrl,folder,shared,deleted,size,lastModifiedDateTime,root'
    $FullDeltaUri = "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?`$select=$DeltaSelect&`$top=999"

    try {
        # Where does this drive start: checkpoint > stored delta token > full scan. Full scans
        # always walk the delta ground truth. A PrincipalCount pre-filter was tried here and
        # removed: paged list enumeration serves STALE principal counts on large, busy lists
        # (linked items kept reading the inherited count days after their links were created),
        # silently under-reporting shares.
        $Checkpoint = Get-DriveCheckpoint
        $Mode = 'Full'
        $Uri = $null
        $PassId = $ScanId
        $ItemsSeen = [int64]0
        $DroppedReads = 0
        $Resumed = $false
        $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter $TenantFilter -DriveId $Drive.id
        if ($Checkpoint -and $Checkpoint.CurrentUri -and [string]$Checkpoint.CurrentMode -in @('Full', 'Incremental')) {
            $Mode = [string]$Checkpoint.CurrentMode
            $Uri = [string]$Checkpoint.CurrentUri
            $PassId = [string]($Checkpoint.PassId ?? $ScanId)
            $ItemsSeen = [int64]($Checkpoint.ItemsSeen ?? 0)
            $DroppedReads = [int]($Checkpoint.DroppedReads ?? 0)
            $Resumed = $true
        } elseif (-not $ForceFull -and $DriveState.ResumeUri -and [string]$DriveState.ResumeMode -in @('Full', 'Incremental')) {
            # A previous scan stopped this drive part way; carry on from where it got to.
            $Mode = [string]$DriveState.ResumeMode
            $Uri = [string]$DriveState.ResumeUri
            $PassId = [string]($DriveState.ResumePassId ?? $ScanId)
            $ItemsSeen = [int64]($DriveState.ResumeItemsSeen ?? 0)
            $DroppedReads = [int]($DriveState.ResumeDropped ?? 0)
            $Resumed = $true
        } elseif (-not $ForceFull -and $DriveState.DeltaLink -and $null -ne $DriveState.RowCount) {
            $Mode = 'Incremental'
            $Uri = [string]$DriveState.DeltaLink
        }

        # Every row the drive holds, by item: a changed item's rows are tombstoned before it is
        # re-read, and rows written for an earlier occurrence of an item in this scan are
        # tombstoned when it appears again, so only its last occurrence survives.
        $RowsByItem = @{}
        $StoredRows = 0
        foreach ($Row in (Get-CIPPSharingLinksRowKeysByPrefix -TenantFilter $TenantFilter -Prefix "${DriveKeySegment}_")) {
            if (-not $Row.RowKey) { continue }
            $StoredRows++
            $ItemKey = [string]$Row.itemId
            if (-not $RowsByItem.ContainsKey($ItemKey)) { $RowsByItem[$ItemKey] = [System.Collections.Generic.List[object]]::new() }
            $RowsByItem[$ItemKey].Add($Row)
        }
        if ($Mode -eq 'Incremental' -and -not $Resumed -and $StoredRows -lt [int]$DriveState.RowCount) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: drive '$($Drive.name)' ($SiteUrl) holds $StoredRows of its $($DriveState.RowCount) rows; scanning it in full" -sev Info
            $Mode = 'Full'
            $Uri = $null
        }
        if (-not $Uri) { $Uri = $FullDeltaUri }

        # A library's own permissions can change without its root reaching the delta, so an
        # incremental scan re-reads that root; an inheriting library's old root rows are dropped.
        $RootItemId = $null
        $ExtraItems = @()
        if ($Mode -eq 'Incremental' -and -not $Resumed) {
            if ($ReadRoot) {
                try {
                    $Root = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root?`$select=$DeltaSelect" -tenantid $TenantFilter -asapp $true
                    $ExtraItems = @([pscustomobject]@{ id = $Root.id; name = $Root.name; webUrl = $Root.webUrl; folder = $Root.folder; size = $Root.size; lastModifiedDateTime = $Root.lastModifiedDateTime; root = @{}; shared = @{} })
                } catch {
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: could not re-read the root of '$($Drive.name)' ($SiteUrl); keeping its rows until the next scan: $($_.Exception.Message)" -sev Debug
                }
            } elseif ($DriveState.RootItemId) {
                $ExtraItems = @([pscustomobject]@{ id = [string]$DriveState.RootItemId; root = @{} })
            }
        }

        $DeltaLink = $null
        $DriveFailed = $false
        while ($Uri) {
            try {
                $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction -extraHeaders @{ Prefer = 'hierarchicalsharing, deltashowremovedasdeleted, deltatraversepermissiongaps, deltashowsharingchanges' }
            } catch {
                $ErrorMessage = $_.Exception.Message
                if ($Uri -ne $FullDeltaUri -and $ErrorMessage -match 'resync|SyncStateNotFound|Gone|410') {
                    # Token or stored position invalidated server-side; the drive needs a fresh full enumeration.
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: delta position for drive '$($Drive.name)' on '$SiteUrl' expired; falling back to full scan" -sev Debug
                    $Mode = 'Full'
                    $Uri = $FullDeltaUri
                    $PassId = $ScanId
                    $ItemsSeen = 0
                    $DroppedReads = 0
                    continue
                }
                if ($ErrorMessage -match 'Access to this site has been blocked') {
                    # Site locked mid-scan: links are inactive, so leave the drive state stale
                    # for finalisation to prune rather than protecting this drive's rows.
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: drive '$($Drive.name)' on '$SiteUrl' is locked; leaving its rows for pruning" -sev Info
                    Remove-DriveCheckpoint
                    Complete-Drive
                    return @()
                }
                if ($ErrorMessage -match 'throttl|too many requests|429|503|504|service unavailable|gateway time') {
                    # Left incomplete: the drive run's post-execution redrives it from the checkpoint.
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: throttled or unavailable mid-scan on drive '$($Drive.name)' ($SiteUrl); it will resume from its checkpoint" -sev Info
                    return @()
                }
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: failed scanning drive '$($Drive.name)' on '$SiteUrl': $ErrorMessage" -sev Warning
                $DriveFailed = $true
                break
            }

            $ItemsSeen = $ItemsSeen + @($Page.value).Count
            $Buffer = [System.Collections.Generic.List[object]]::new()
            $TombstoneRows = [System.Collections.Generic.List[object]]::new()
            foreach ($PageItem in @($ExtraItems) + @($Page.value)) {
                $ItemKey = [string]$PageItem.id
                if ($PageItem.root) { $RootItemId = $ItemKey }
                if ($RowsByItem.ContainsKey($ItemKey)) {
                    # Incremental: every changed item invalidates the rows it had - deleted items,
                    # items no longer shared and items whose link set changed all converge on a
                    # fresh read. Full: only rows from an earlier occurrence in this scan; older
                    # rows are overwritten or swept once the drive completes.
                    $Keep = [System.Collections.Generic.List[object]]::new()
                    foreach ($Row in $RowsByItem[$ItemKey]) {
                        if ($Mode -eq 'Incremental' -or [string]$Row.ScanId -eq $PassId) { $TombstoneRows.Add($Row) } else { $Keep.Add($Row) }
                    }
                    $RowsByItem[$ItemKey] = $Keep
                }
                if ($PageItem.shared -and -not $PageItem.deleted -and ($ReadRoot -or -not $PageItem.root)) { $Buffer.Add($PageItem) }
            }
            $ExtraItems = @()

            # Rows for this page: permission lookups happen per page so the checkpoint below
            # never advances past work that has not been persisted.
            $PageRows = [System.Collections.Generic.List[object]]::new()
            Add-CIPPSharingRows -Buffer $Buffer -Drive $Drive -Site $SiteContext -InternalDomains $InternalDomains -TenantFilter $TenantFilter -RowsOut $PageRows -DropCounter ([ref]$DroppedReads)

            if ($TombstoneRows.Count -gt 0) {
                $null = Remove-CIPPAzDataTableEntity @LinksTable -Entity $TombstoneRows.ToArray() -Force
            }
            if ($PageRows.Count -gt 0) {
                $null = Add-CIPPAzDataTableEntity @LinksTable -Entity $PageRows.ToArray() -Force
                foreach ($Row in $PageRows) {
                    if (-not $RowsByItem.ContainsKey($Row.itemId)) { $RowsByItem[$Row.itemId] = [System.Collections.Generic.List[object]]::new() }
                    $RowsByItem[$Row.itemId].Add(@{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey; ETag = '*'; ScanId = $PassId })
                }
            }

            if ($Page.'@odata.deltaLink') {
                $DeltaLink = [string]$Page.'@odata.deltaLink'
                $Uri = $null
            } else {
                $Uri = [string]$Page.'@odata.nextLink'
            }

            # This page's rows are persisted, so the resume position may advance past it.
            if ($Uri) {
                Save-DriveCheckpoint -State @{ CurrentUri = $Uri; CurrentMode = $Mode; PassId = $PassId; ItemsSeen = $ItemsSeen; DroppedReads = $DroppedReads }
            }
        }

        if ($DriveFailed -or $DroppedReads -gt 0) {
            # Throttled/failed batch reads mean some items were not rewritten this scan. A full
            # scan keeps every row and runs full again next time; an incremental one keeps its old
            # token so the next scan replays the same changes, re-reading what was dropped.
            if ($DroppedReads -gt 0) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Sharing links: $DroppedReads permission reads dropped on drive '$($Drive.name)' ($SiteUrl); keeping existing rows and retrying next scan" -sev Warning
            }
            $KeepToken = if ($Mode -eq 'Incremental') { [string]$DriveState.DeltaLink } else { '' }
            Set-DriveState -DeltaLink $KeepToken
        } else {
            if ($Mode -eq 'Full') {
                # The scan rewrote every shared item's rows with this scan's id; anything left
                # under the drive's prefix without it is a link that no longer exists.
                $null = Remove-CIPPSharingLinksRowsByPrefix -TenantFilter $TenantFilter -Prefix "${DriveKeySegment}_" -ExceptScanId $PassId
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
