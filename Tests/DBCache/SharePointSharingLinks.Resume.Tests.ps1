# Pester tests for the resumable, delta-persisted sharing-links scan.
#
# The scan's correctness lives in state transitions - checkpoints, delta tokens, tombstones,
# completion counting - so these tests run the real activity, finaliser, state helpers and the
# real Add-CIPPDbItem against an in-memory stand-in for table storage that understands the
# handful of OData filter shapes the code generates. Graph is scripted per test.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # --- in-memory table storage -------------------------------------------------------------
    # Entities are stored per table and cloned on read so mutations only land via an explicit
    # write-back, the same contract the real service gives the code under test.
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }

    function Get-FakeTableRows {
        param([string]$TableName)
        if (-not $script:FakeTables.ContainsKey($TableName)) { $script:FakeTables[$TableName] = [System.Collections.Generic.List[object]]::new() }
        # Comma operator: return the List itself, not its unrolled elements.
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
        # Clone PSCustomObjects so later caller-side mutation cannot silently edit the store.
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
        # CmdletBinding so the fake honours the caller's -ErrorAction, like the real wrapper.
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
        # CmdletBinding so the fake honours the caller's -ErrorAction, like the real cmdlet.
        [CmdletBinding()]
        param($TableName, $Entity, [switch]$Force)
        if ($script:FailScanRowUpdates -gt 0 -and $Entity.RowKey -eq 'scan') {
            $script:FailScanRowUpdates--
            # Faithful to AzBobbyTables: an ETag conflict surfaces as a NON-terminating error,
            # so only call sites passing -ErrorAction Stop can catch and retry it.
            Write-Error 'The update condition specified in the request was not satisfied. Status: 412 (Precondition Failed) ErrorCode: UpdateConditionNotSatisfied'
            return
        }
        # An update overwrites by definition - the insert-only rule above applies to Add alone.
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

    # Graph GET routed through a per-test handler; the shared default serves the drives listing.
    function New-GraphGetRequest {
        param($uri, $tenantid, $scope, $AsApp, [bool]$noPagination, $NoAuthCheck, [bool]$skipTokenCache, $Caller, [switch]$ComplexFilter, [switch]$CountOnly, [switch]$IncludeResponseHeaders, [hashtable]$extraHeaders, [switch]$ReturnRawResponse, [switch]$SkipValueExtraction, [switch]$Stream, [switch]$UseCertificate, $Headers)
        $script:GraphGetCalls.Add($uri)
        & $script:GraphGetHandler $uri
    }

    # Every requested item gets one anonymous view link back, unless a test swaps the handler.
    function New-GraphBulkRequest {
        param($tenantid, $NoAuthCheck, $scope, $asapp, $Requests, $NoPaginateIds, $Version, $Headers)
        foreach ($Request in @($Requests)) {
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
    # The scan-state helpers live one function per file (the Craft runtime resolves functions
    # by file name); load every one of them plus the collector.
    foreach ($HelperFile in (Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache') -Filter '*-CIPPSharingLinks*.ps1')) {
        . $HelperFile.FullName
    }
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSharePointSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-DBCacheSharePointSiteSharingLinks.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sharing/Push-StoreSharePointSharingLinks.ps1')

    # --- shared builders ------------------------------------------------------------------------
    function New-SiteItem {
        param([string]$ScanId, [string]$SiteId = 'contoso.sharepoint.com,site1,web1', [string]$SiteUrl = 'https://contoso.sharepoint.com/sites/one')
        [pscustomobject]@{
            FunctionName    = 'DBCacheSharePointSiteSharingLinks'
            TenantFilter    = 'contoso.com'
            SiteId          = $SiteId
            SiteName        = 'Site One'
            SiteUrl         = $SiteUrl
            IsPersonalSite  = $false
            InternalDomains = @('contoso.com')
            ScanId          = $ScanId
            Slice           = 1
            ForceFull       = $false
            QueueId         = $null
            QueueName       = 'Sharing Links - test'
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

    # The scan row is written inline by the fan-out parent (no public initialiser), so tests
    # seed and read it as raw entities.
    function Initialize-TestScan {
        param([string]$ScanId, [int]$TotalSites, [bool]$FullSweep = $false)
        Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
            PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = $ScanId; PendingSites = $TotalSites; TotalSites = $TotalSites
            FailedSites = '[]'; FullSweep = $FullSweep; StartedUtc = '2026-08-12T00:00:00Z'
        }
    }

    function Get-TestScanRow {
        (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -eq 'scan' } | Select-Object -First 1
    }
}

Describe 'Resumable sharing-links scan' {

    BeforeEach {
        $script:FakeTables = @{}
        $script:Orchestrations = [System.Collections.Generic.List[object]]::new()
        $script:QueueUpdates = [System.Collections.Generic.List[object]]::new()
        $script:GraphGetCalls = [System.Collections.Generic.List[string]]::new()
        $script:FailScanRowUpdates = 0
        $env:CIPP_SHARINGLINKS_FULLSCAN_DAYS = $null

        # Default Graph: one drive with one delta page holding one shared file.
        $script:GraphGetHandler = {
            param($Uri)
            if ($Uri -match '/sites/[^/]+/drives') {
                return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents'; driveType = 'documentLibrary' })
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

    Context 'full scan of a site' {
        It 'writes rows stamped with the scan id and stores the drive delta token' {
            $ScanId = 'scan-full-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            $Rows = @((Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -like 'SharePointSharingLinks-b!driveone_01ITEMA_*' })
            $Rows.Count | Should -Be 1
            $Rows[0].RunId | Should -Be $ScanId

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -Be 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=fresh'
            $DriveState.LastScanId | Should -Be $ScanId
            $DriveState.LastFullScanUtc | Should -Not -BeNullOrEmpty
        }

        It 'prunes rows a full rescan of the drive did not rewrite' {
            $ScanId = 'scan-full-2'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01GONE_permOld'

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01GONE_permOld'
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMA_perm-01ITEMA'
        }

        It 'decrements the pending counter and only finalises on the last site' {
            $ScanId = 'scan-full-3'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)
            ([int](Get-TestScanRow).PendingSites) | Should -Be 1
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-Count'

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId -SiteId 'contoso.sharepoint.com,site2,web2' -SiteUrl 'https://contoso.sharepoint.com/sites/two')
            ([int](Get-TestScanRow).PendingSites) | Should -Be 0
            $CountRow = (Get-FakeTableRows -TableName 'CippReportingDB') | Where-Object { $_.RowKey -eq 'SharePointSharingLinks-Count' }
            # Two sites sharing one fake drive id: the same rows get upserted, so one link remains.
            [int]$CountRow.DataCount | Should -Be 1
        }
    }

    Context 'incremental scan from a stored delta token' {
        BeforeEach {
            $script:ScanId = 'scan-incr-1'
            Initialize-TestScan -ScanId $script:ScanId -TotalSites 1
            # Drive completed a full scan recently, so the next scan is incremental.
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'delta-b!driveone'; DriveId = 'b!driveone'; SiteId = 'contoso.sharepoint.com,site1,web1'
                DeltaLink = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored'
                LastScanId = 'previous-scan'; LastScanUtc = '2026-08-10T00:00:00Z'; LastFullScanUtc = '2026-08-10T00:00:00Z'
            }
            # Existing cache rows: X will change, Y is untouched, Z will arrive deleted.
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMX_permOld'
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMY_permKeep'
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!driveone_01ITEMZ_permDead'
        }

        It 'scans from the stored token, tombstones changed items and keeps untouched rows' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents' }) }
                if ($Uri -eq 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=stored') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMX'; name = 'x.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                        [pscustomobject]@{ id = '01ITEMZ'; name = 'z.docx'; deleted = [pscustomobject]@{ state = 'deleted' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=newer'
                }
                throw "Unrouted GET: $Uri"
            }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $script:ScanId)

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

        It 'falls back to a full scan when the stored token is rejected' {
            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives') { return @([pscustomobject]@{ id = 'b!driveone'; name = 'Documents' }) }
                if ($Uri -match 'token=stored') { throw 'resyncRequired: The delta token is no longer valid, and the app must obtain a new one.' }
                if ($Uri -match '/root/delta') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMY'; name = 'y.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=rebuilt'
                }
                throw "Unrouted GET: $Uri"
            }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $script:ScanId)

            # The full rescan rewrote Y and pruned everything it did not rewrite.
            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMY_perm-01ITEMY'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMX_permOld'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!driveone_01ITEMY_permKeep'

            $DriveState = Get-CIPPSharingLinksDriveState -TenantFilter 'contoso.com' -DriveId 'b!driveone'
            $DriveState.DeltaLink | Should -BeLike '*token=rebuilt'
            $DriveState.LastFullScanUtc | Should -Not -Be '2026-08-10T00:00:00Z'
        }
    }

    Context 'resume from a checkpoint' {
        It 'skips completed drives and resumes the current drive at the checkpointed page' {
            $ScanId = 'scan-resume-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            # Checkpoint CRUD is nested inside the activity, so the resume position is seeded as
            # the raw entity the activity persists.
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'
                RowKey       = 'chk-contoso.sharepoint.com,site1,web1'
                ScanId       = $ScanId
                StateJson    = (@{
                        CompletedDrives = @('b!drivedone')
                        CurrentDriveId  = 'b!driveone'
                        CurrentUri      = 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=page7'
                        CurrentMode     = 'Full'
                    } | ConvertTo-Json -Compress)
            }

            $script:GraphGetHandler = {
                param($Uri)
                if ($Uri -match '/sites/[^/]+/drives') {
                    return @(
                        [pscustomobject]@{ id = 'b!drivedone'; name = 'Done' }
                        [pscustomobject]@{ id = 'b!driveone'; name = 'Documents' }
                    )
                }
                if ($Uri -match 'token=page7') {
                    return New-DeltaPage -Items @(
                        [pscustomobject]@{ id = '01ITEMC'; name = 'c.docx'; shared = [pscustomobject]@{ scope = 'anonymous' } }
                    ) -DeltaLink 'https://graph.microsoft.com/beta/drives/b!driveone/root/delta?token=done'
                }
                throw "Unrouted GET: $Uri"
            }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            # No call ever targeted the completed drive or the start of the current one.
            @($script:GraphGetCalls | Where-Object { $_ -match 'drivedone' }).Count | Should -Be 0
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-b!driveone_01ITEMC_perm-01ITEMC'
            # Site finished, so the checkpoint is gone.
            (Get-FakeTableRows -TableName 'CippSharingLinksState') | Where-Object { $_.RowKey -like 'chk-*' } | Should -BeNullOrEmpty
        }
    }

    Context 'superseded scans' {
        It 'exits without scanning or touching the counter when a newer scan owns the state' {
            Initialize-TestScan -ScanId 'scan-new' -TotalSites 5

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId 'scan-old')

            $script:GraphGetCalls.Count | Should -Be 0
            ([int](Get-TestScanRow).PendingSites) | Should -Be 5
        }
    }

    Context 'completion counter under contention' {
        It 'counts a site exactly once however many times its task is dispatched' {
            $ScanId = 'scan-dup-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2

            # The same site task delivered twice - a retry mechanism re-firing a task that in
            # fact completed, or a duplicate delivery. The second run rescans harmlessly but
            # must not decrement the counter again, or the scan would finalise early while the
            # second site is still pending.
            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)
            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            ([int](Get-TestScanRow).PendingSites) | Should -Be 1
            Get-CacheRowKeys | Should -Not -Contain 'SharePointSharingLinks-Count'
        }

        It 'retries a lost ETag race instead of silently dropping the decrement' {
            $ScanId = 'scan-race-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 1
            # First conditional write of the scan row 412s, exactly like losing the race to a
            # concurrently finishing site. The retry must re-read and land the decrement.
            $script:FailScanRowUpdates = 1

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            ([int](Get-TestScanRow).PendingSites) | Should -Be 0
            # Pending reached zero, so finalisation ran and wrote the count row.
            Get-CacheRowKeys | Should -Contain 'SharePointSharingLinks-Count'
        }
    }

    Context 'site failure' {
        It 'records the failed site and still decrements the counter' {
            $ScanId = 'scan-fail-1'
            Initialize-TestScan -ScanId $ScanId -TotalSites 2
            $script:GraphGetHandler = { param($Uri) throw 'drives listing failed' }

            Push-DBCacheSharePointSiteSharingLinks -Item (New-SiteItem -ScanId $ScanId)

            $Scan = Get-TestScanRow
            ([int]$Scan.PendingSites) | Should -Be 1
            @($Scan.FailedSites | ConvertFrom-Json) | Should -Contain 'contoso.sharepoint.com,site1,web1'
        }
    }

    Context 'finalisation' {
        It 'prunes rows and state of drives the scan never saw, but keeps failed sites intact' {
            $ScanId = 'scan-final-1'
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = $ScanId; PendingSites = 0; TotalSites = 3
                FailedSites = '["contoso.sharepoint.com,siteF,webF"]'; FullSweep = $false; StartedUtc = '2026-08-12T00:00:00Z'
            }
            # Current drive, vanished drive, and a drive on the failed site.
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
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = $ScanId; PendingSites = 0; TotalSites = 1
                FailedSites = '[]'; FullSweep = $true; StartedUtc = '2026-08-12T00:00:00Z'
            }
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!current_01ITEMA_p1' -RunId $ScanId
            Add-CacheRow -RowKey 'SharePointSharingLinks-b!orphandrive_01ITEMO_p1' -RunId 'ancient-scan'

            Push-StoreSharePointSharingLinks -TenantFilter 'contoso.com' -ScanId $ScanId

            $Keys = Get-CacheRowKeys
            $Keys | Should -Contain 'SharePointSharingLinks-b!current_01ITEMA_p1'
            $Keys | Should -Not -Contain 'SharePointSharingLinks-b!orphandrive_01ITEMO_p1'
        }

        It 'does no housekeeping when a newer scan owns the state' {
            Add-CIPPAzDataTableEntity -TableName 'CippSharingLinksState' -Entity @{
                PartitionKey = 'contoso.com'; RowKey = 'scan'; ScanId = 'scan-newer'; PendingSites = 3; TotalSites = 3
                FailedSites = '[]'; FullSweep = $true; StartedUtc = '2026-08-12T00:00:00Z'
            }
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
