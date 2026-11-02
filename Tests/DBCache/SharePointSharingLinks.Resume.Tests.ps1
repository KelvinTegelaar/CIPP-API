# Pester tests for the per-drive, marker-completed, resumable sharing-links scan.
#
# The scan's correctness lives in state transitions - checkpoints, delta tokens, tombstones,
# marker-based completion - so these tests run the real activity, finaliser, state helpers and
# the real table helpers against an in-memory stand-in for table storage that understands the
# handful of OData filter shapes the code generates. Graph is scripted per test.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

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
        $script:QueueUpdates.Add([pscustomobject]@{ RowKey = $RowKey; TotalTasks = $TotalTasks; Name = $Name })
    }
    function Start-CIPPOrchestrator {
        param($InputObject, $InputObjectGuid, [switch]$CallerIsQueueTrigger)
        $script:Orchestrations.Add($InputObject)
    }

    function New-GraphGetRequest {
        param($uri, $tenantid, $scope, $AsApp, [bool]$noPagination, $NoAuthCheck, [bool]$skipTokenCache, $Caller, [switch]$ComplexFilter, [switch]$CountOnly, [switch]$IncludeResponseHeaders, [hashtable]$extraHeaders, [switch]$ReturnRawResponse, [switch]$SkipValueExtraction, [switch]$Stream, [switch]$UseCertificate, $Headers)
        $script:GraphGetCalls.Add($uri)
        if ($uri -match '/delta') { $script:DeltaPrefer.Add([string]$extraHeaders.Prefer) }
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
            $script:ReadItemIds.Add($ItemId)
            if ($ItemId -like '*ROOT') {
                [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'inherited'; roles = @('read'); inheritedFrom = [pscustomobject]@{ id = 'site' } }) } }
                continue
            }
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

    foreach ($HelperFile in (Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPCore/Public/SharingLinks') -Filter '*.ps1')) {
        . $HelperFile.FullName
    }
    foreach ($HelperFile in (Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache') -Filter '*-CIPPSharingLinks*.ps1')) {
        . $HelperFile.FullName
    }
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSharePointSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-DBCacheSharePointSiteSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-StoreSharePointSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-SharingLinksDispatchDrives.ps1')

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

    function New-DispatchItem {
        param($SiteItem, [int]$Round = 0)
        @{ Parameters = @{ TenantFilter = $SiteItem.TenantFilter; ScanId = $SiteItem.ScanId; InternalDomains = $SiteItem.InternalDomains; ForceFull = $SiteItem.ForceFull; Round = $Round } }
    }

    # Runs a site task and its post-execution, and returns the drive tasks that queued.
    function New-DriveTasks {
        param($SiteItem)
        $null = Push-DBCacheSharePointSiteSharingLinks -Item $SiteItem
        Push-SharingLinksDispatchDrives -Item (New-DispatchItem -SiteItem $SiteItem)
        $Run = $script:Orchestrations[$script:Orchestrations.Count - 1]
        $null = $script:Orchestrations.Remove($Run)
        @($Run.Batch)
    }

    # Runs a site task and its post-execution, then every queued run's tasks followed by that
    # run's post-execution, the way the orchestrator would.
    function Invoke-SiteAndDrives {
        param($SiteItem)
        $null = Push-DBCacheSharePointSiteSharingLinks -Item $SiteItem
        Push-SharingLinksDispatchDrives -Item (New-DispatchItem -SiteItem $SiteItem)
        $Cursor = 0
        while ($Cursor -lt $script:Orchestrations.Count) {
            $Queued = $script:Orchestrations[$Cursor]
            $Cursor++
            foreach ($Task in @($Queued.Batch)) { $null = Push-DBCacheSharePointSiteSharingLinks -Item $Task }
            if ($Queued.PostExecution) { Push-SharingLinksDispatchDrives -Item @{ Parameters = $Queued.PostExecution.Parameters } }
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
        param([string]$RowKey, [string]$ScanId = 'previous-scan')
        Add-CIPPAzDataTableEntity -TableName 'CippSharingLinks' -Entity @{
            PartitionKey = 'contoso.com'; RowKey = $RowKey; ScanId = $ScanId; itemId = $RowKey.Split('_')[1]; id = $RowKey; ETag = '*'
        }
    }

    function Get-CacheRowKeys {
        @((Get-FakeTableRows -TableName 'CippSharingLinks') | ForEach-Object { $_.RowKey }) | Sort-Object
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
        $script:ReadItemIds = [System.Collections.Generic.List[string]]::new()
        $script:DeltaPrefer = [System.Collections.Generic.List[string]]::new()
        $env:CIPP_SHARINGLINKS_FULLSCAN_DAYS = $null

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

            @(Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)).Count | Should -Be 0
            $script:Orchestrations.Count | Should -Be 0
            # The dispatch total the drive tasks complete against matches what was dispatched.
            $DrivesRow = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'drives-*' }
            [int]$DrivesRow.DriveCount | Should -Be 1

            Push-SharingLinksDispatchDrives -Item (New-DispatchItem -SiteItem (New-SiteItem -ScanId $ScanId))
            $Tasks = @($script:Orchestrations[0].Batch)
            $Tasks.Count | Should -Be 1
            $Tasks[0].DriveId | Should -Be 'b!docs'
            $Tasks[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/one'
            @($Tasks[0].InternalDomains) | Should -Be @('contoso.com')
        }

        It 'queues every unfinished drive of the scan as one run of at most three at a time' {
            $ScanId = 'scan-dispatch-4'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'drives-site1'; ScanId = $ScanId; DriveCount = 2; SiteUrl = 'https://one'
                DrivesJson = '[{"id":"b!one","name":"One"},{"id":"b!two","name":"Two"}]'
            }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'drives-site2'; ScanId = $ScanId; DriveCount = 1; SiteUrl = 'https://two'
                DrivesJson = '[{"id":"b!three","name":"Three"}]'
            }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'ddone-site1~b!two'; ScanId = $ScanId }

            Push-SharingLinksDispatchDrives -Item @{ Parameters = @{ TenantFilter = 'contoso.com'; ScanId = $ScanId; Round = 3 } }

            $script:Orchestrations.Count | Should -Be 1
            $script:Orchestrations[0].OrchestratorName | Should -Be 'SharingLinksDrives_contoso.com_r4'
            $script:Orchestrations[0].MaxConcurrency | Should -Be 3
            @($script:Orchestrations[0].Batch.DriveId) | Should -Be @('b!one', 'b!three')
            $script:Orchestrations[0].PostExecution.FunctionName | Should -Be 'SharingLinksDispatchDrives'
            $script:Orchestrations[0].PostExecution.Parameters.Round | Should -Be 4
            ((Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'scan' }).Phase | Should -Be 'Round 4: 2 libraries (2 full)'
        }

        It 'queues nothing when every drive finished or the scan was superseded' {
            Initialize-TestScan -ScanId 'scan-dispatch-5' -TotalSites 1
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'drives-site1'; ScanId = 'scan-dispatch-5'; DriveCount = 1; DrivesJson = '[{"id":"b!one","name":"One"}]'
            }
            Push-SharingLinksDispatchDrives -Item @{ Parameters = @{ TenantFilter = 'contoso.com'; ScanId = 'scan-older'; Round = 1 } }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'ddone-site1~b!one'; ScanId = 'scan-dispatch-5' }
            Push-SharingLinksDispatchDrives -Item @{ Parameters = @{ TenantFilter = 'contoso.com'; ScanId = 'scan-dispatch-5'; Round = 1 } }
            $script:Orchestrations.Count | Should -Be 0
        }

        It 'completes the site as failed when the drive listing is refused' {
            $ScanId = 'scan-dispatch-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            $script:GraphGetHandler = { param($Uri) throw 'The request has been throttled' }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            $Marker = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'done-contoso.sharepoint.com,site1,web1' }
            [string]$Marker.Failed | Should -Be 'True'
            # Not the last site, so no finalisation.
            Get-StateRowKeys | Should -Not -Contain 'summary'
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

    Context 'full scan of a team-site drive' {
        It 'walks the delta ground truth, prunes stale rows and stores the token' {
            $ScanId = 'scan-team-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CacheRow -RowKey 'b!driveone_01GONE_permOld'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId)

            $Rows = @((Get-FakeTableRows -TableName 'CippSharingLinks') | Where-Object { $_.RowKey -like 'b!driveone_01ITEMA_*' })
            $Rows.Count | Should -Be 1
            $Rows[0].ScanId | Should -Be $ScanId
            # The full-scan prune removed what this scan did not rewrite.
            Get-CacheRowKeys | Should -Not -Contain 'b!driveone_01GONE_permOld'

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=fresh'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.LastFullScanUtc | Should -Not -BeNullOrEmpty
            # Only items with their own permissions carry the shared facet, so inheriting files cost no permission read.
            $script:DeltaPrefer.Count | Should -BeGreaterThan 0
            # deltashowsharingchanges only works alongside deltashowremovedasdeleted and deltatraversepermissiongaps.
            foreach ($Value in 'hierarchicalsharing', 'deltashowremovedasdeleted', 'deltatraversepermissiongaps', 'deltashowsharingchanges') {
                $script:DeltaPrefer.Where({ $_ -notmatch $Value }).Count | Should -Be 0
            }

            # Last drive of the last site: the scan finalised and wrote the count row.
            Get-StateRowKeys | Should -Contain 'summary'
            Get-StateRowKeys | Should -Contain 'final'
        }
    }

    Context 'full scan with an item listed twice' {
        It 'keeps only the last occurrence, dropping rows written for the earlier one' {
            $ScanId = 'scan-dup-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -match 'token=page2') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMA'; name = 'a.docx' }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=fresh'
                }
                if ($Uri -match '/root/delta') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMA'; name = 'a.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -NextLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page2'
                }
                throw "Unrouted GET: $Uri"
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId)

            # Its later occurrence no longer carries its own permissions, so the link is gone.
            Get-CacheRowKeys | Should -Not -Contain 'b!driveone_01ITEMA_perm-01ITEMA'
            [int](Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').RowCount | Should -Be 0
        }
    }

    Context 'full scan with dropped permission reads' {
        It 'keeps existing rows and defers the sweep when batch reads are throttled away' {
            $ScanId = 'scan-drop-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CacheRow -RowKey 'b!driveone_01SURVIVOR_permOld'
            # Every permission read comes back throttled inside the batch.
            Mock New-GraphBulkRequest {
                foreach ($Request in @($Requests)) {
                    [pscustomobject]@{ id = $Request.id; status = 429; body = $null }
                }
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId)

            # Nothing was rewritten, so nothing may be pruned - and the drive must not claim a
            # completed full scan, so the next run starts over.
            Get-CacheRowKeys | Should -Contain 'b!driveone_01SURVIVOR_permOld'
            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            [string]$DriveState.DeltaLink | Should -BeNullOrEmpty
            [string]$DriveState.LastFullScanUtc | Should -BeNullOrEmpty
            # The drive still completes its task so the scan can finalise.
            Get-StateRowKeys | Should -Contain 'summary'
        }
    }

    Context 'classic full scan (personal site)' {
        It 'writes rows stamped with the scan id and stores the drive delta token' {
            $ScanId = 'scan-full-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            $Rows = @((Get-FakeTableRows -TableName 'CippSharingLinks') | Where-Object { $_.RowKey -like 'b!driveone_01ITEMA_*' })
            $Rows.Count | Should -Be 1
            $Rows[0].ScanId | Should -Be $ScanId

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -Be 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=fresh'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.LastFullScanUtc | Should -Not -BeNullOrEmpty
        }

        It 'only finalises when the last site completes' {
            $ScanId = 'scan-full-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)
            Get-StateRowKeys | Should -Not -Contain 'summary'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -SiteId 'contoso.sharepoint.com,site2,web2' -SiteUrl 'https://contoso.sharepoint.com/sites/two' -IsPersonalSite $true)
            $CountRow = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'summary' }
            # Two sites sharing one fake drive id: the same rows get upserted, so one link remains.
            [int]$CountRow.LinkCount | Should -Be 1
        }
    }

    Context 'incremental scan from a stored delta token' {
        BeforeEach {
            $script:ScanId = 'scan-incr-1'
            $script:LastFullScanUtc = '2026-01-01T00:00:00.0000000+00:00'
            Initialize-TestScan -ScanId $script:ScanId -TotalSites 1
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'
                DeltaLink = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored'
                LastScanId = 'previous-scan'; LastScanUtc = $script:LastFullScanUtc; LastFullScanUtc = $script:LastFullScanUtc; RowCount = 3
            }
            Add-CacheRow -RowKey 'b!driveone_01ITEMX_permOld'
            Add-CacheRow -RowKey 'b!driveone_01ITEMY_permKeep'
            Add-CacheRow -RowKey 'b!driveone_01ITEMZ_permDead'
            $script:IncrementalHandler = {
                param($Uri)
                if ($Uri -match '/drives/b!driveone/root\?') { return [pscustomobject]@{ id = '01ROOT'; name = 'root'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents'; folder = [pscustomobject]@{}; root = [pscustomobject]@{} } }
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -eq 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMX'; name = 'x.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                        [pscustomobject]@{ id = '01ITEMZ'; name = 'z.docx'; deleted = [pscustomobject]@{ state = 'deleted' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=newer'
                }
                if ($Uri -match '/root/delta') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMY'; name = 'y.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=rebuilt'
                }
                throw "Unrouted GET: $Uri"
            }
            $script:GraphGetHandler = $script:IncrementalHandler
        }

        It 'scans from the stored token, tombstones changed items and keeps untouched rows' {
            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            $Keys = Get-CacheRowKeys
            $Keys | Should -Not -Contain 'b!driveone_01ITEMX_permOld'   # replaced
            $Keys | Should -Contain 'b!driveone_01ITEMX_perm-01ITEMX'   # fresh read
            $Keys | Should -Contain 'b!driveone_01ITEMY_permKeep'       # untouched
            $Keys | Should -Not -Contain 'b!driveone_01ITEMZ_permDead'  # deleted item

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=newer'
            [int]$DriveState.RowCount | Should -Be 2
            # A library holding its own permissions has its root re-read every incremental scan.
            $script:ReadItemIds | Should -Contain '01ROOT'
            $DriveState.RootItemId | Should -Be '01ROOT'
            # Incremental completion must not claim a full scan happened.
            $DriveState.LastFullScanUtc | Should -Be $script:LastFullScanUtc
        }

        It 'falls back to a classic full scan when the stored token is rejected' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match 'token=stored') { throw 'resyncRequired: The delta token is no longer valid, and the app must obtain a new one.' }
                & $script:IncrementalHandler $Uri
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'b!driveone_01ITEMY_perm-01ITEMY'
            $Keys | Should -Not -Contain 'b!driveone_01ITEMX_permOld'
            $Keys | Should -Not -Contain 'b!driveone_01ITEMY_permKeep'

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=rebuilt'
            $DriveState.LastFullScanUtc | Should -Not -Be $script:LastFullScanUtc
        }

        It 'scans in full when the drive holds fewer rows than it recorded' {
            Remove-CIPPAzDataTableEntity -TableName 'CippSharingLinks' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'b!driveone_01ITEMY_permKeep' }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            @($script:GraphGetCalls | Where-Object { $_ -match 'token=stored' }).Count | Should -Be 0
            Get-CacheRowKeys | Should -Be @('b!driveone_01ITEMY_perm-01ITEMY')
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').DeltaLink | Should -BeLike '*token=rebuilt'
        }

        It 'scans in full when the drive state predates row counts' {
            $State = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'delta-b!driveone' }
            $State.PSObject.Properties.Remove('RowCount')

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            @($script:GraphGetCalls | Where-Object { $_ -match 'token=stored' }).Count | Should -Be 0
            Get-CacheRowKeys | Should -Be @('b!driveone_01ITEMY_perm-01ITEMY')
        }

        It 'keeps only the last occurrence of an item that appears twice' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match 'token=stored') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMQ'; name = 'q.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -NextLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page2'
                }
                if ($Uri -match 'token=page2') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMQ'; name = 'q.docx'; deleted = [pscustomobject]@{ state = 'deleted' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=newer'
                }
                & $script:IncrementalHandler $Uri
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            Get-CacheRowKeys | Should -Not -Contain 'b!driveone_01ITEMQ_perm-01ITEMQ'
            [int](Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').RowCount | Should -Be 3
        }

        It 'keeps its old token when permission reads drop, so the next scan replays the changes' {
            Mock New-GraphBulkRequest {
                foreach ($Request in @($Requests)) {
                    [pscustomobject]@{ id = $Request.id; status = 429; body = $null }
                }
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $script:ScanId)

            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').DeltaLink | Should -BeLike '*token=stored'
            Get-StateRowKeys | Should -Contain 'summary'
        }
    }

    Context 'resume' {
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
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMC_perm-01ITEMC'
            # Drive finished: checkpoint gone, drive marker present, scan finalised.
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' } | Should -BeNullOrEmpty
            Get-StateRowKeys | Should -Contain 'summary'
        }
    }

    Context 'throttle mid-scan and redrive' {
        BeforeEach {
            # Page 1 succeeds; page 2 throttles out even after the helper's own retries, then recovers.
            $script:Page2Failures = 1
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                if ($Uri -match 'token=page2') {
                    if ($script:Page2Failures-- -gt 0) { throw 'The request has been throttled' }
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMB'; name = 'b.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=done'
                }
                if ($Uri -match '/root/delta') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMA'; name = 'a.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -NextLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page2'
                }
                throw "Unrouted GET: $Uri"
            }
        }

        It 'leaves the drive unfinished at its checkpoint' {
            $ScanId = 'scan-throttle-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1

            $DriveTask = @(New-DriveTasks -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true))[0]
            Push-DBCacheSharePointSiteSharingLinks -Item $DriveTask

            # Page 1 persisted and the checkpoint points at page 2; the drive is neither completed
            # nor failed, and the task queued nothing itself.
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMA_perm-01ITEMA'
            $Checkpoint = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' }
            $Checkpoint.StateJson | Should -BeLike '*token=page2*'
            ($Checkpoint.StateJson | ConvertFrom-Json).ItemsSeen | Should -Be 1
            $script:Orchestrations.Count | Should -Be 0
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'ddone-*' } | Should -BeNullOrEmpty
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone') | Should -BeNullOrEmpty
        }

        It 'redrives the unfinished drive from its checkpoint in the next round' {
            $ScanId = 'scan-throttle-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            @($script:Orchestrations.OrchestratorName) | Should -Be @('SharingLinksDrives_contoso.com_r1', 'SharingLinksDrives_contoso.com_r2')
            # Round 2 resumed at page 2 rather than restarting the drive.
            @($script:GraphGetCalls | Where-Object { $_ -match '\$top=999' }).Count | Should -Be 1
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMB_perm-01ITEMB'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').DeltaLink | Should -BeLike '*token=done'
            Get-StateRowKeys | Should -Contain 'summary'
        }

        It 'stops a drive that saved no page in a round, keeping its rows and position for the next scan' {
            $ScanId = 'scan-throttle-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:Page2Failures = 100
            Add-CacheRow -RowKey 'b!driveone_01OLD_permOld'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            # Round 1 saved a page, round 2 saved none: no third round.
            @($script:Orchestrations.OrchestratorName) | Should -Be @('SharingLinksDrives_contoso.com_r1', 'SharingLinksDrives_contoso.com_r2')
            Get-CacheRowKeys | Should -Contain 'b!driveone_01OLD_permOld'
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMA_perm-01ITEMA'
            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.ResumeUri | Should -BeLike '*token=page2'
            $DriveState.ResumeMode | Should -Be 'Full'
            $DriveState.ResumePassId | Should -Be $ScanId
            $DriveState.ResumeItemsSeen | Should -Be 1
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' } | Should -BeNullOrEmpty
            Get-StateRowKeys | Should -Contain 'summary'
        }

        It 'keeps dropped permission reads from an earlier round, so the finished pass prunes nothing' {
            $ScanId = 'scan-throttle-6'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:Page2Failures = 1
            Add-CacheRow -RowKey 'b!driveone_01ITEMA_permOld'
            # Round 1's permission read for page 1 is throttled away; round 2 reads page 2 cleanly.
            $script:BulkFailuresLeft = 1
            Mock New-GraphBulkRequest {
                foreach ($Request in @($Requests)) {
                    if ($script:BulkFailuresLeft-- -gt 0) { [pscustomobject]@{ id = $Request.id; status = 429; body = $null }; continue }
                    $ItemId = ($Request.url -split '/')[3]
                    [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = "perm-$ItemId"; roles = @('read'); link = [pscustomobject]@{ scope = 'anonymous'; type = 'view'; webUrl = "https://share/$ItemId" } }) } }
                }
            }

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            # The pass finished in round 2 but remembers round 1's drop: nothing pruned, next scan runs full.
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMA_permOld'
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMB_perm-01ITEMB'
            [string](Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').DeltaLink | Should -BeNullOrEmpty
        }

        It 'resumes after a 503 instead of failing the drive' {
            $ScanId = 'scan-throttle-7'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $Handler = $script:GraphGetHandler
            $Unavailable = [ref]1
            $script:GraphGetHandler = { param($Uri) if ($Uri -match 'token=page2' -and ($Unavailable.Value = $Unavailable.Value - 1) -ge 0) { throw 'Response status code does not indicate success: 503 (Service Unavailable).' }; & $Handler $Uri }.GetNewClosure()
            $script:Page2Failures = 0

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            @($script:Orchestrations.OrchestratorName) | Should -Be @('SharingLinksDrives_contoso.com_r1', 'SharingLinksDrives_contoso.com_r2')
            Get-CacheRowKeys | Should -Contain 'b!driveone_01ITEMB_perm-01ITEMB'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone').DeltaLink | Should -BeLike '*token=done'
        }

        It 'resumes a stopped drive on the next scan and keeps the rows its earlier pass wrote' {
            $ScanId = 'scan-throttle-4'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:Page2Failures = 0
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'; DeltaLink = ''
                ResumeUri = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page2'; ResumeMode = 'Full'; ResumePassId = 'scan-earlier'
            }
            Add-CacheRow -RowKey 'b!driveone_01ITEMA_perm-01ITEMA' -ScanId 'scan-earlier'
            Add-CacheRow -RowKey 'b!driveone_01STALE_permOld' -ScanId 'scan-ancient'

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            @($script:GraphGetCalls | Where-Object { $_ -match '\$top=999' }).Count | Should -Be 0
            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'b!driveone_01ITEMA_perm-01ITEMA'
            $Keys | Should -Contain 'b!driveone_01ITEMB_perm-01ITEMB'
            $Keys | Should -Not -Contain 'b!driveone_01STALE_permOld'
            ((Get-FakeTableRows -TableName 'CippSharingLinks') | Where-Object { $_.RowKey -eq 'b!driveone_01ITEMB_perm-01ITEMB' }).ScanId | Should -Be 'scan-earlier'
            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=done'
            [string]$DriveState.ResumeUri | Should -BeNullOrEmpty
        }

        It 'rescans in full when the stored position is rejected' {
            $ScanId = 'scan-throttle-5'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:Page2Failures = 0
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'; DeltaLink = ''
                ResumeUri = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=expired'; ResumeMode = 'Full'; ResumePassId = 'scan-earlier'
            }
            Add-CacheRow -RowKey 'b!driveone_01GONE_permOld' -ScanId 'scan-earlier'
            $Handler = $script:GraphGetHandler
            $script:GraphGetHandler = { param($Uri) if ($Uri -match 'token=expired') { throw 'resyncRequired: The delta token is no longer valid' }; & $Handler $Uri }.GetNewClosure()

            Invoke-SiteAndDrives -SiteItem (New-SiteItem -ScanId $ScanId -IsPersonalSite $true)

            @($script:GraphGetCalls | Where-Object { $_ -match '\$top=999' }).Count | Should -Be 1
            $Keys = Get-CacheRowKeys
            $Keys | Should -Not -Contain 'b!driveone_01GONE_permOld'
            $Keys | Should -Contain 'b!driveone_01ITEMA_perm-01ITEMA'
            $Keys | Should -Contain 'b!driveone_01ITEMB_perm-01ITEMB'
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
            Get-StateRowKeys | Should -Not -Contain 'summary'
        }
    }

    Context 'library root permissions' {
        It 'reads library roots only where the library holds its own permissions' {
            $ScanId = 'scan-preflight-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/_api/web/lists') {
                    return @(
                        [pscustomobject]@{ ItemCount = 1200; HasUniqueRoleAssignments = $false; RootFolder = [pscustomobject]@{ ServerRelativeUrl = '/sites/one/Shared Documents' } }
                        [pscustomobject]@{ ItemCount = 7; HasUniqueRoleAssignments = $true; RootFolder = [pscustomobject]@{ ServerRelativeUrl = '/sites/one/Private' } }
                    )
                }
                if ($Uri -match '/sites/[^/]+/drives\?') {
                    return @(
                        [pscustomobject]@{ id = 'b!shared'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }
                        [pscustomobject]@{ id = 'b!private'; name = 'Private'; webUrl = 'https://contoso.sharepoint.com/sites/one/Private' }
                        [pscustomobject]@{ id = 'b!unknown'; name = 'Unknown'; webUrl = 'https://contoso.sharepoint.com/sites/one/Unknown' }
                    )
                }
                if ($Uri -match '/drives/(b![a-z]+)/root/delta') {
                    $Id = $Matches[1].Substring(2)
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = "01${Id}ROOT"; name = 'root'; root = [pscustomobject]@{}; shared = [pscustomobject]@{} }
                        [pscustomobject]@{ id = "01${Id}FILE"; name = 'a.docx'; shared = [pscustomobject]@{ scope = 'users' } }
                    ) -DeltaLink "https://graph.microsoft.com/beta/drives/b!$Id/root/delta?token=fresh"
                }
                throw "Unrouted GET: $Uri"
            }
            $SiteItem = New-SiteItem -ScanId $ScanId
            $SiteItem | Add-Member -NotePropertyName SharePointScope -NotePropertyValue 'https://contoso.sharepoint.com/.default'

            Invoke-SiteAndDrives -SiteItem $SiteItem

            @($script:Orchestrations[0].Batch | Sort-Object DriveId | ForEach-Object { "$($_.DriveId)=$($_.ReadRoot)" }) | Should -Be @('b!private=True', 'b!shared=False', 'b!unknown=True')
            # SharePoint's item count rides along for scan progress; an unplaced library has none.
            $DrivesJson = ((Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'drives-*' }).DrivesJson | ConvertFrom-Json
            @($DrivesJson | Sort-Object id | ForEach-Object { "$($_.id)=$($_.itemCount)" }) | Should -Be @('b!private=7', 'b!shared=1200', 'b!unknown=-1')
            $script:ReadItemIds | Should -Not -Contain '01sharedROOT'
            $script:ReadItemIds | Should -Contain '01privateROOT'
            $script:ReadItemIds | Should -Contain '01unknownROOT'
            # Every file with its own permissions is still read.
            @($script:ReadItemIds | Where-Object { $_ -like '*FILE' }).Count | Should -Be 3
        }

        It 'reads every library root when SharePoint cannot be asked' {
            $ScanId = 'scan-preflight-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            $SiteItem = New-SiteItem -ScanId $ScanId
            $SiteItem | Add-Member -NotePropertyName SharePointScope -NotePropertyValue 'https://contoso.sharepoint.com/.default'
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/_api/web/lists') { throw 'Unauthorized' }
                if ($Uri -match '/sites/[^/]+/drives\?') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/one/Shared%20Documents' }) }
                throw "Unrouted GET: $Uri"
            }

            @(New-DriveTasks -SiteItem $SiteItem)[0].ReadRoot | Should -BeTrue
        }

        It 'drops an inheriting library root rows on an incremental scan' {
            $ScanId = 'scan-preflight-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'
                DeltaLink = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored'; LastScanId = 'previous-scan'; RowCount = 1; RootItemId = '01ROOT'
            }
            Add-CacheRow -RowKey 'b!driveone_01ROOT_permGuest'
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match 'token=stored') { return New-DeltaPage -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=newer' }
                throw "Unrouted GET: $Uri"
            }
            $DriveTask = New-SiteItem -ScanId $ScanId
            $DriveTask | Add-Member -NotePropertyName DriveId -NotePropertyValue 'b!driveone'
            $DriveTask | Add-Member -NotePropertyName DriveName -NotePropertyValue 'Documents'
            $DriveTask | Add-Member -NotePropertyName ReadRoot -NotePropertyValue $false
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'drives-contoso.sharepoint.com,site1,web1'; ScanId = $ScanId; DriveCount = 1 }

            Push-DBCacheSharePointSiteSharingLinks -Item $DriveTask

            Get-CacheRowKeys | Should -Not -Contain 'b!driveone_01ROOT_permGuest'
            $script:ReadItemIds.Count | Should -Be 0
        }
    }

    Context 'scan in progress' {
        BeforeEach {
            $script:StartedUtc = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = 'scan-live'; TotalSites = 3; StartedUtc = $script:StartedUtc; QueueId = 'queue-1'; Phase = 'Round 2: 1 library (1 full)'
            }
        }

        It 'reports a scan as running until it finalises' {
            $Status = Get-CIPPSharingLinksScanStatus -TenantFilter 'contoso.com'
            $Status.inProgress | Should -BeTrue
            $Status.queueId | Should -Be 'queue-1'
            $Status.startedUtc | Should -Be $script:StartedUtc
            $Status.phase | Should -Be 'Round 2: 1 library (1 full)'

            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'final'; ScanId = 'scan-live' }
            (Get-CIPPSharingLinksScanStatus -TenantFilter 'contoso.com').inProgress | Should -BeFalse
        }

        It 'treats a scan unfinished after 24 hours as abandoned' {
            $Row = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'scan' }
            $Row.StartedUtc = [DateTimeOffset]::UtcNow.AddHours(-25).ToString('o')
            (Get-CIPPSharingLinksScanStatus -TenantFilter 'contoso.com').inProgress | Should -BeFalse
        }

        It 'breaks the running scan down by library' {
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'drives-site1'; ScanId = 'scan-live'; DriveCount = 3; SiteName = 'Site One'; SiteUrl = 'https://one'
                DrivesJson = '[{"id":"b!a","name":"Docs","itemCount":2000},{"id":"b!b","name":"Big","itemCount":990000},{"id":"b!c","name":"Small","itemCount":3}]'
            }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{ PartitionKey = 'contoso.com'; RowKey = 'ddone-site1~b!a'; ScanId = 'scan-live' }
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'chk-site1~b!b'; ScanId = 'scan-live'; StateJson = '{"CurrentUri":"x","CurrentMode":"Full","PassId":"scan-live","ItemsSeen":412000}'
            }

            $Status = Get-CIPPSharingLinksScanStatus -TenantFilter 'contoso.com' -Libraries

            $Status.librariesTotal | Should -Be 3
            $Status.librariesDone | Should -Be 1
            $Big = @($Status.libraries).Where({ $_.library -eq 'Big' })[0]
            $Big.status | Should -Be 'scanning'
            $Big.itemsSeen | Should -Be 412000
            $Big.itemCount | Should -Be 990000
            $Big.mode | Should -Be 'Full'
            @($Status.libraries).Where({ $_.library -eq 'Docs' })[0].status | Should -Be 'done'
            # Queued libraries are only counted, not listed.
            @($Status.libraries).Where({ $_.library -eq 'Small' }).Count | Should -Be 0
        }

        It 'does not start a second scan while one is running' {
            Set-CIPPDBCacheSharePointSharingLinks -TenantFilter 'contoso.com' -QueueId 'queue-2'

            $script:Orchestrations.Count | Should -Be 0
            $script:GraphGetCalls.Count | Should -Be 0
            ((Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'scan' }).ScanId | Should -Be 'scan-live'
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
            Add-CacheRow -RowKey 'b!current_01ITEMA_p1' -ScanId $ScanId
            Add-CacheRow -RowKey 'b!vanished_01ITEMB_p1'
            Add-CacheRow -RowKey 'b!unreachable_01ITEMC_p1'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId $ScanId

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'b!current_01ITEMA_p1'
            $Keys | Should -Not -Contain 'b!vanished_01ITEMB_p1'
            $Keys | Should -Contain 'b!unreachable_01ITEMC_p1'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!vanished') | Should -BeNullOrEmpty
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!unreachable') | Should -Not -BeNullOrEmpty

            $CountRow = (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'summary' }
            [int]$CountRow.LinkCount | Should -Be 2
        }

        It 'sweeps every row the scan did not write when the scan was a full sweep' {
            $ScanId = 'scan-final-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1 -FullSweep $true
            Add-CacheRow -RowKey 'b!current_01ITEMA_p1' -ScanId $ScanId
            Add-CacheRow -RowKey 'b!orphandrive_01ITEMO_p1' -ScanId 'ancient-scan'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId $ScanId

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'b!current_01ITEMA_p1'
            $Keys | Should -Not -Contain 'b!orphandrive_01ITEMO_p1'
        }

        It 'does no housekeeping when a newer scan owns the state' {
            Initialize-TestScan -ScanId 'scan-newer' -TotalSites 3 -FullSweep $true
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!inflight'; DriveId = 'b!inflight'; SiteId = 's1'
                DeltaLink = 'x'; LastScanId = 'scan-newer'; LastScanUtc = 'x'; LastFullScanUtc = 'x'
            }
            Add-CacheRow -RowKey 'b!inflight_01ITEMN_p1' -ScanId 'scan-newer'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId 'scan-older'

            Get-CacheRowKeys | Should -Contain 'b!inflight_01ITEMN_p1'
            (Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!inflight') | Should -Not -BeNullOrEmpty
        }
    }
}
