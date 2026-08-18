# Pester tests for the per-drive, marker-completed, resumable sharing-links scan.
#
# The scan's correctness lives in state transitions - checkpoints, delta tokens, tombstones,
# marker-based completion - so these tests run the real activity, finaliser, state helpers and
# the real Add-CIPPDbItem against an in-memory stand-in for table storage that understands the
# handful of OData filter shapes the code generates. Graph is scripted per test.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # --- in-memory table storage -------------------------------------------------------------
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }

    function Get-FakeTableRows {
        param([string]$TableName)
        if (-not $script:FakeTables.ContainsKey($TableName)) { $script:FakeTables[$TableName] = [System.Collections.Generic.List[object]]::new() }
        , $script:FakeTables[$TableName]
    }

    function Invoke-FakeTableFilter {
        param($Rows, [string]$Filter)
        $Result = @($Rows)
        if ($Filter -match "PartitionKey eq '([^']*)'") { $Pk = $Matches[1]; $Result = @($Result | Where-Object { $_.PartitionKey -eq $Pk }) }
        if ($Filter -match "RowKey eq '([^']*)'") { $Rk = $Matches[1]; $Result = @($Result | Where-Object { $_.RowKey -eq $Rk }) }
        if ($Filter -match "RowKey ge '([^']*)'") { $Ge = $Matches[1]; $Result = @($Result | Where-Object { [string]::CompareOrdinal([string]$_.RowKey, $Ge) -ge 0 }) }
        if ($Filter -match "RowKey lt '([^']*)'") { $Lt = $Matches[1]; $Result = @($Result | Where-Object { [string]::CompareOrdinal([string]$_.RowKey, $Lt) -lt 0 }) }
        $Result
    }

    function ConvertTo-FakeEntity {
        param($Entity)
        if ($Entity -is [hashtable]) { return [pscustomobject]$Entity }
        $Clone = [ordered]@{}
        foreach ($Property in $Entity.PSObject.Properties) { $Clone[$Property.Name] = $Property.Value }
        [pscustomobject]$Clone
    }

    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter, $Property, [switch]$Count)
        $Rows = Get-FakeTableRows -TableName $TableName
        foreach ($Row in (Invoke-FakeTableFilter -Rows $Rows -Filter $Filter)) { ConvertTo-FakeEntity -Entity $Row }
    }

    function Add-CIPPAzDataTableEntity {
        [CmdletBinding()]
        param($TableName, $Entity, [switch]$Force, [switch]$CreateTableIfNotExists)
        $Rows = Get-FakeTableRows -TableName $TableName
        foreach ($Item in @($Entity)) {
            if ($null -eq $Item) { continue }
            $New = ConvertTo-FakeEntity -Entity $Item
            $Existing = $Rows | Where-Object { $_.PartitionKey -eq $New.PartitionKey -and $_.RowKey -eq $New.RowKey } | Select-Object -First 1
            if ($Existing) {
                # Faithful to the real wrapper: without -Force the operation is an insert, and
                # writing over an existing entity fails (first writer wins).
                if (-not $Force) {
                    Write-Error "The specified entity already exists. Status: 409 (Conflict) ErrorCode: EntityAlreadyExists (RowKey: $($New.RowKey))"
                    continue
                }
                [void]$Rows.Remove($Existing)
            }
            $Rows.Add($New)
        }
    }

    function Remove-CIPPAzDataTableEntity {
        param($TableName, $Entity, [switch]$Force)
        $Rows = Get-FakeTableRows -TableName $TableName
        foreach ($Item in @($Entity)) {
            if ($null -eq $Item) { continue }
            $Existing = $Rows | Where-Object { $_.PartitionKey -eq $Item.PartitionKey -and $_.RowKey -eq $Item.RowKey } | Select-Object -First 1
            if ($Existing) { [void]$Rows.Remove($Existing) }
        }
    }

    function Update-AzDataTableEntity {
        [CmdletBinding()]
        param($TableName, $Entity, [switch]$Force)
        Add-CIPPAzDataTableEntity -TableName $TableName -Entity $Entity -Force
    }

    # --- other dependency stubs ---------------------------------------------------------------
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com' } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) [string]$Value }
    function Update-CippQueueEntry {
        param($RowKey, $Status, $Name, $TotalTasks, [switch]$IncrementTotalTasks)
        $script:QueueUpdates.Add([pscustomobject]@{ RowKey = $RowKey; TotalTasks = $TotalTasks })
    }
    function Start-CIPPOrchestrator {
        param($InputObject, $InputObjectGuid, [switch]$CallerIsQueueTrigger)
        $script:Orchestrations.Add($InputObject)
    }

    function New-GraphGetRequest {
        param($uri, $tenantid, $scope, $AsApp, [bool]$noPagination, $NoAuthCheck, [bool]$skipTokenCache, $Caller, [switch]$ComplexFilter, [switch]$CountOnly, [switch]$IncludeResponseHeaders, [hashtable]$extraHeaders, [switch]$ReturnRawResponse, [switch]$SkipValueExtraction, [switch]$Stream, [switch]$UseCertificate, $Headers)
        $script:GraphGetCalls.Add($uri)
        & $script:GraphGetHandler $uri
    }

    # Serves both bulk shapes the activity issues: classic per-item permission reads
    # (.../items/{id}/permissions -> body.value) and Principal-mode driveItem reads
    # (.../listitems/{id}/driveItem?...$expand=permissions -> body is the driveItem).
    function New-GraphBulkRequest {
        param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers)
        foreach ($Request in @($Requests)) {
            if ($Request.url -match '^sites/[^/]+/lists/[^/]+/items/([^/]+)/driveItem') {
                $ListItemId = $Matches[1]
                [pscustomobject]@{
                    id     = $Request.id
                    status = 200
                    body   = [pscustomobject]@{
                        id          = "01DRV$ListItemId"
                        name        = "item-$ListItemId.docx"
                        size        = 1
                        permissions = @(
                            [pscustomobject]@{
                                id    = "perm-$ListItemId"
                                roles = @('read')
                                link  = [pscustomobject]@{ scope = 'anonymous'; type = 'view'; webUrl = "https://share/$ListItemId" }
                            }
                        )
                    }
                }
                continue
            }
            $ItemId = ($Request.url -split '/')[3]
            [pscustomobject]@{
                id     = $Request.id
                status = 200
                body   = [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            id    = "perm-$ItemId"
                            roles = @('read')
                            link  = [pscustomobject]@{ scope = 'anonymous'; type = 'view'; webUrl = "https://share/$ItemId" }
                        }
                    )
                }
            }
        }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPDbItem.ps1')
    foreach ($HelperFile in (Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache') -Filter '*-CIPPSharingLinks*.ps1')) {
        . $HelperFile.FullName
    }
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSharePointSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-DBCacheSharePointSiteSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-StoreSharePointSharingLinks.ps1')

    # --- shared builders ------------------------------------------------------------------------
    function New-SiteItem {
        param([string]$ScanId, [string]$SiteId = 'contoso.sharepoint.com,site1,web1', [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/one', [bool]$IsPersonalSite = $false, [bool]$ForceFull = $false)
        [pscustomobject]@{
            FunctionName    = 'DBCacheSharePointSiteSharingLinks'
            TenantFilter    = 'contoso.com'
            SiteId          = $SiteId
            SiteName        = 'Site One'
            SiteUrl         = $SiteUrl
            IsPersonalSite  = $IsPersonalSite
            InternalDomains = @('contoso.com')
            ScanId          = $ScanId
            ForceFull       = $ForceFull
            QueueId         = $null
            QueueName       = 'Sharing Links - test'
        }
    }

    # Runs a site task, then every drive task it queued (and any tasks those queue in turn),
    # the way the orchestrator would.
    function Invoke-SiteAndDrives {
        param($SiteItem)
        Push-DBCacheSharePointSiteSharingLinks -Item $SiteItem
        $Cursor = 0
        while ($Cursor -lt $script:Orchestrations.Count) {
            $Queued = $script:Orchestrations[$Cursor]
            $Cursor++
            foreach ($Task in @($Queued.Batch)) { Push-DBCacheSharePointSiteSharingLinks -Item $Task }
        }
    }

    function New-DeltaPage {
        param($Items = @(), [string]$NextLink, [string]$DeltaLink)
        $Page = [ordered]@{ value = @($Items) }
        if ($NextLink) { $Page['@odata.nextLink'] = $NextLink }
        if ($DeltaLink) { $Page['@odata.deltaLink'] = $DeltaLink }
        [pscustomobject]$Page
    }

    function Add-CacheRow {
        param([string]$RowKey, [string]$RunId = 'previous-scan')
        Add-CIPPAzDataTableEntity -TableName 'CippReportingDB' -Entity @{
            PartitionKey = 'contoso.com'; RowKey = $RowKey; Type = 'SharePointSharingLinks'; RunId = $RunId; Data = '{"id":"x"}'; ETag = '*'
        }
    }

    function Get-CacheRowKeys {
        @((Get-FakeTableRows -TableName 'CippReportingDB') | ForEach-Object { $_.RowKey }) | Sort-Object
    }

    function Initialize-TestScan {
        param([string]$ScanId, [int]$TotalSites, [bool]$FullSweep = $false)
        Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
            PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = $ScanId; TotalSites = $TotalSites
            FullSweep = $FullSweep; StartedUtc = '2026-08-12T00:00:00Z'
        }
    }

    function Get-StateRowKeys {
        @((Get-FakeTableRows -TableName 'CippSharingLinksState') | ForEach-Object { $_.RowKey }) | Sort-Object
    }
}

Describe 'Per-drive sharing-links scan' {

    BeforeEach {
        $script:FakeTables = @{}
        $script:Orchestrations = [System.Collections.Generic.List[object]]::new()
        $script:QueueUpdates = [System.Collections.Generic.List[object]]::new()
        $script:GraphGetCalls = [System.Collections.Generic.List[string]]::new()
        $env:CIPP_SHARINGLINKS_FULLSCAN_DAYS = $null
        $env:CIPP_SHARINGLINKS_TIMEBOX_SECONDS = $null

        # Default Graph: a personal-site style drive whose full scan is a classic delta walk
        # with one shared file, plus the Principal-mode routes for team-site tests.
        $script:GraphGetHandler = {
            param($Uri)
            if ($Uri -match '/sites/[^/]+/drives\?') {
                return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; driveType = 'documentLibrary'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' })
            }
            if ($Uri -match '/drives/b!driveone/list\?') { return [pscustomobject]@{ id = 'list1' } }
            if ($Uri -match '/drives/b!driveone/root/permissions') {
                return @([pscustomobject]@{ id = 'g1' }, [pscustomobject]@{ id = 'g2' }, [pscustomobject]@{ id = 'g3' })
            }
            if ($Uri -match '/lists/list1/items\?') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{ id = '11'; fields = [pscustomobject]@{ PrincipalCount = 3 } }
                        [pscustomobject]@{ id = '12'; fields = [pscustomobject]@{ PrincipalCount = 4 } } # extra principal = shared
                    )
                }
            }
            if ($Uri -match 'token=latest') {
                return New-DeltaPage -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=captured'
            }
            if ($Uri -match '/root/delta') {
                return New-DeltaPage -Items @(
                    [pscustomobject]@{ id = '01ITEMA'; name = 'a.docx'; shared = [pscustomobject]@{ scope = 'anonymous' }; size = 1 }
                    [pscustomobject]@{ id = '01ITEMB'; name = 'b.docx'; size = 2 } # not shared
                ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=fresh'
            }
            throw "Unrouted GET: $Uri"
        }
    }

    Context 'site task fan-out' {
        It 'dispatches one drive task per drive and skips the Preservation Hold Library' {
            $ScanId = 'scan-dispatch-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') {
                    return @(
                        [pscustomobject]@{ id = 'b!docs'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }
                        [pscustomobject]@{ id = 'b!phl'; name = 'Preservation Hold Library'; webUrl = 'https://contoso.sharepoint.com/sites/one/PreservationHoldLibrary' }
                    )
                }
                throw "Unrouted GET: $Uri"
            }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            $script:Orchestrations.Count | Should -Be 1
            $Tasks = @($script:Orchestrations[0].Batch)
            $Tasks.Count | Should -Be 1
            $Tasks[0].DriveId | Should -Be 'b!docs'
            # The dispatch total the drive tasks complete against matches what was dispatched.
            $DrivesRow = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'drives-*' }
            [int]$DrivesRow.DriveCount | Should -Be 1
        }

        It 'completes the site as failed when the drive listing is refused' {
            $ScanId = 'scan-dispatch-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            $script:GraphGetHandler = { param($Uri) throw 'The request has been throttled' }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            $Marker = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'done-contoso.sharepoint.com,site1,web1' }
            [string]$Marker.Failed | Should -Be 'True'
            # Not the last site, so no finalisation.
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-Count'
        }

        It 'skips a locked site un-failed so finalisation prunes its dead links' {
            $ScanId = 'scan-dispatch-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            $script:GraphGetHandler = { param($Uri) throw 'Access to this site has been blocked. Please contact the administrator to resolve this problem.' }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            # Completed un-failed and nothing dispatched: the site's stale drive rows are left
            # unprotected, which is what lets finalisation prune its now-inactive links.
            $Marker = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'done-contoso.sharepoint.com,site1,web1' }
            [string]$Marker.Failed | Should -Be 'False'
            $script:Orchestrations.Count | Should -Be 0
        }
    }

    Context 'Principal-mode full scan of a team-site drive' {
        It 'permission-reads only items whose principal count deviates and captures a delta token' {
            $ScanId = 'scan-principal-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01GONE_permOld'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId)

            # Only the deviating list item (id 12) was read; its row carries the scan id.
            $Rows = @((Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -like 'SharePointSharingLinks-b!driveone_01DRV12_*' })
            $Rows.Count | Should -Be 1
            $Rows[0].RunId | Should -Be $ScanId
            # The full-scan prune removed what this scan did not rewrite.
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01GONE_permOld'

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=captured'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.LastFullScanUtc | Should -Not -BeNullOrEmpty

            # Last drive of the last site: the scan finalised and wrote the count row.
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-Count'
            Get-StateRowKeys | Should -Contain 'final'
        }
    }

    Context 'Principal-mode scan with dropped permission reads' {
        It 'keeps existing rows and defers the sweep when batch reads are throttled away' {
            $ScanId = 'scan-principal-drop-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01SURVIVOR_permOld'
            # Every Principal-mode driveItem read comes back throttled.
            Mock New-GraphBulkRequest {
                foreach ($Request in @($Requests)) {
                    [pscustomobject]@{ id = $Request.id; status = 429; body = $null }
                }
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId)

            # Nothing was rewritten, so nothing may be pruned - and the drive must not claim a
            # completed full scan, so the next run starts over.
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!driveone_01SURVIVOR_permOld'
            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            [string]$DriveState.DeltaLink | Should -BeNullOrEmpty
            [string]$DriveState.LastFullScanUtc | Should -BeNullOrEmpty
            # The drive still completes its task so the scan can finalise.
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-Count'
        }
    }

    Context 'classic full scan (personal site)' {
        It 'writes rows stamped with the scan id and stores the drive delta token' {
            $ScanId = 'scan-full-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            $Rows = @((Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -like 'SharePointSharingLinks-b!driveone_01ITEMA_*' })
            $Rows.Count | Should -Be 1
            $Rows[0].RunId | Should -Be $ScanId

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -Be 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=fresh'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.LastFullScanUtc | Should -Not -BeNullOrEmpty
        }

        It 'only finalises when the last site completes' {
            $ScanId = 'scan-full-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-Count'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -SiteId 'contoso.sharepoint.com,site2,web2' -SiteUrl 'https://contoso.sharepoint.com/sites/two' -IsPersonalSite $true)
            $CountRow = (Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -eq 'SharePointSharingLinks-Count' }
            # Two sites sharing one fake drive id: the same rows get upserted, so one link remains.
            [int]$CountRow.DataCount | Should -Be 1
        }
    }

    Context 'incremental scan from a stored delta token' {
        BeforeEach {
            $script:ScanId = 'scan-incr-1'
            Initialize-TestScan -ScanId $script:ScanId -TotalSites 1
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'
                DeltaLink = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored'
                LastScanId = 'previous-scan'; LastScanUtc = '2026-08-10T00:00:00Z'; LastFullScanUtc = '2026-08-10T00:00:00Z'
            }
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMX_permOld'
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMY_permKeep'
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMZ_permDead'
        }

        It 'scans from the stored token, tombstones changed items and keeps untouched rows' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -eq 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMX'; name = 'x.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                        [pscustomobject]@{ id = '01ITEMZ'; name = 'z.docx'; deleted = [pscustomobject]@{ state = 'deleted' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=newer'
                }
                throw "Unrouted GET: $Uri"
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            $Keys = Get-CacheRowKeys
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMX_permOld'   # replaced
            $Keys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMX_perm-01ITEMX'   # fresh read
            $Keys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMY_permKeep'       # untouched
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMZ_permDead'  # deleted item

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=newer'
            # Incremental completion must not claim a full scan happened.
            $DriveState.LastFullScanUtc | Should -Be '2026-08-10T00:00:00Z'
        }

        It 'falls back to a classic full scan when the stored token is rejected' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -match 'token=stored') { throw 'resyncRequired: The delta token is no longer valid, and the app must obtain a new one.' }
                if ($Uri -match '/root/delta') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMY'; name = 'y.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=rebuilt'
                }
                throw "Unrouted GET: $Uri"
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMY_perm-01ITEMY'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMX_permOld'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMY_permKeep'

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=rebuilt'
            $DriveState.LastFullScanUtc | Should -Not -Be '2026-08-10T00:00:00Z'
        }
    }

    Context 'resume and timebox' {
        It 'resumes a drive task at the checkpointed page' {
            $ScanId = 'scan-resume-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'
                RowKey       = 'chk-contoso.sharepoint.com,site1,web1~b!driveone'
                ScanId       = $ScanId
                StateJson    = (@{
                        CurrentUri  = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page7'
                        CurrentMode = 'Full'
                    } | ConvertTo-Json -Compress)
            }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'drives-contoso.sharepoint.com,site1,web1'; ScanId = $ScanId; DriveCount = 1
            }
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match 'token=page7') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMC'; name = 'c.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=done'
                }
                throw "Unrouted GET: $Uri"
            }

            $DriveTask = New-SiteItem -ScanId $ScanId
            $DriveTask | Add-Member -NotePropertyName DriveId -NotePropertyValue 'b!driveone'
            $DriveTask | Add-Member -NotePropertyName DriveName -NotePropertyValue 'Documents'
            Push-DBCacheSharePointSiteSharingLinks -Item $DriveTask

            # No call restarted the drive from the beginning.
            @($script:GraphGetCalls | Where-Object { $_ -match '\$top=999' }).Count | Should -Be 0
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMC_perm-01ITEMC'
            # Drive finished: checkpoint gone, drive marker present, scan finalised.
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' } | Should -BeNullOrEmpty
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-Count'
        }

        It 'checkpoints and requeues itself when the timebox is spent instead of completing' {
            $ScanId = 'scan-timebox-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $env:CIPP_SHARINGLINKS_TIMEBOX_SECONDS = '1'
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -match '/root/delta') {
                    Start-Sleep -Seconds 2 # burn the timebox on the first page
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMA'; name = 'a.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -NextLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page2'
                }
                throw "Unrouted GET: $Uri"
            }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)
            $DriveTask = @($script:Orchestrations[0].Batch)[0]
            Push-DBCacheSharePointSiteSharingLinks -Item $DriveTask

            # Page 1's rows are persisted, the resume position is saved, and the task re-queued
            # itself rather than finishing the drive.
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMA_perm-01ITEMA'
            $Checkpoint = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' }
            $Checkpoint.StateJson | Should -BeLike '*token=page2*'
            $Requeued = @($script:Orchestrations | Where-Object { $_.OrchestratorName -like 'SharingLinksResume_*' })
            $Requeued.Count | Should -Be 1
            @($Requeued[0].Batch)[0].DriveId | Should -Be 'b!driveone'
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'ddone-*' } | Should -BeNullOrEmpty
        }
    }

    Context 'superseded scans and duplicate dispatch' {
        It 'exits without scanning when a newer scan owns the state' {
            Initialize-TestScan -ScanId 'scan-new' -TotalSites 5

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId 'scan-old')

            $script:GraphGetCalls.Count | Should -Be 0
            Get-StateRowKeys | Should -Not -Contain 'done-contoso.sharepoint.com,site1,web1'
        }

        It 'counts a site exactly once however many times its tasks are dispatched' {
            $ScanId = 'scan-dup-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)
            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            @((Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'done-*' }).Count | Should -Be 1
            # One of two sites complete: no finalisation.
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-Count'
        }
    }

    Context 'finalisation' {
        It 'prunes rows and state of drives the scan never saw, but keeps failed sites intact' {
            $ScanId = 'scan-final-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 3
            # The failed site's completion marker is where the failed set now lives.
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'done-contoso.sharepoint.com,siteF,webF'; ScanId = $ScanId; Failed = $true
            }
            foreach ($State in @(
                    @{ RowKey = 'delta-b!current'; DriveId = 'b!current'; SiteId = 's1'; LastScanId = $ScanId }
                    @{ RowKey = 'delta-b!vanished'; DriveId = 'b!vanished'; SiteId = 's2'; LastScanId = 'previous-scan' }
                    @{ RowKey = 'delta-b!unreachable'; DriveId = 'b!unreachable'; SiteId = 'contoso.sharepoint.com,siteF,webF'; LastScanId = 'previous-scan' }
                )) {
                Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity (@{ PartitionKey = 'contoso.com'; DeltaLink = 'x'; LastScanUtc = 'x'; LastFullScanUtc = 'x' } + $State)
            }
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!current_01ITEMA_p1' -RunId $ScanId
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!vanished_01ITEMB_p1'
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!unreachable_01ITEMC_p1'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId $ScanId

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'SharePointSharingLinks-b!current_01ITEMA_p1'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!vanished_01ITEMB_p1'
            $Keys | Should -Contain 'SharePointSharingLinks-b!unreachable_01ITEMC_p1'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!vanished') | Should -BeNullOrEmpty
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!unreachable') | Should -Not -BeNullOrEmpty

            $CountRow = (Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -eq 'SharePointSharingLinks-Count' }
            [int]$CountRow.DataCount | Should -Be 2
        }

        It 'sweeps every row the scan did not write when the scan was a full sweep' {
            $ScanId = 'scan-final-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1 -FullSweep $true
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!current_01ITEMA_p1' -RunId $ScanId
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!orphandrive_01ITEMO_p1' -RunId 'ancient-scan'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId $ScanId

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'SharePointSharingLinks-b!current_01ITEMA_p1'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!orphandrive_01ITEMO_p1'
        }

        It 'does no housekeeping when a newer scan owns the state' {
            Initialize-TestScan -ScanId 'scan-newer' -TotalSites 3 -FullSweep $true
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!inflight'; DriveId = 'b!inflight'; SiteId = 's1'
                DeltaLink = 'x'; LastScanId = 'scan-newer'; LastScanUtc = 'x'; LastFullScanUtc = 'x'
            }
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!inflight_01ITEMN_p1' -RunId 'scan-newer'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId 'scan-older'

            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!inflight_01ITEMN_p1'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!inflight') | Should -Not -BeNullOrEmpty
        }
    }
}
