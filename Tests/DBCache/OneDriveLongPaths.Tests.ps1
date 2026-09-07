# Pester tests for OneDriveLongPaths fan-out, skip-no-UPN, and checkpoint resume.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }

    function Get-FakeTableRows {
        param([string]$TableName)
        if (-not $script:FakeTables.ContainsKey($TableName)) {
            $script:FakeTables[$TableName] = [System.Collections.Generic.List[object]]::new()
        }
        , $script:FakeTables[$TableName]
    }

    function Invoke-FakeTableFilter {
        param($Rows, [string]$Filter)
        $Result = @($Rows)
        if ($Filter -match "PartitionKey eq '([^']*)'") {
            $Pk = $Matches[1]
            $Result = @($Result | Where-Object { $_.PartitionKey -eq $Pk })
        }
        if ($Filter -match "RowKey eq '([^']*)'") {
            $Rk = $Matches[1]
            $Result = @($Result | Where-Object { $_.RowKey -eq $Rk })
        }
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
        foreach ($Row in (Invoke-FakeTableFilter -Rows $Rows -Filter $Filter)) {
            ConvertTo-FakeEntity -Entity $Row
        }
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
                if (-not $Force) { continue }
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

    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'tenant-guid'; defaultDomainName = 'contoso.com' } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) [string]$Value }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name, $TotalTasks, [switch]$IncrementTotalTasks) }
    function Start-CIPPOrchestrator {
        param($InputObject, $InputObjectGuid, [switch]$CallerIsQueueTrigger)
        $script:Orchestrations.Add($InputObject)
    }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) @() }
    function New-GraphGetRequest {
        param($uri, $tenantid, $scope, $AsApp, [bool]$noPagination, $NoAuthCheck, [bool]$skipTokenCache, $Caller, [switch]$ComplexFilter, [switch]$CountOnly, [switch]$IncludeResponseHeaders, [hashtable]$extraHeaders, [switch]$ReturnRawResponse, [switch]$SkipValueExtraction, [switch]$Stream, [switch]$UseCertificate, $Headers)
        & $script:GraphGetHandler $uri $SkipValueExtraction
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPDbItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDriveItemCloudPathLength.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheOneDriveLongPaths.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/OneDrive Long Paths/Push-DBCacheOneDriveLongPaths.ps1')
}

Describe 'Set-CIPPDBCacheOneDriveLongPaths' {
    BeforeEach {
        $script:FakeTables = @{}
        $script:Orchestrations = [System.Collections.Generic.List[object]]::new()
        $env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS = '99999'
    }

    It 'fans out personal sites and passes UPN when usage map has it' {
        $script:GraphGetHandler = {
            param($Uri, $SkipValueExtraction)
            if ($Uri -match '/organization') {
                return @([pscustomobject]@{ displayName = 'Contoso' })
            }
            if ($Uri -match 'getAllSites') {
                return @(
                    [pscustomobject]@{
                        id            = 'contoso-my.sharepoint.com,aaaa,bbbb'
                        webUrl        = 'https://contoso-my.sharepoint.com/personal/known_contoso_com'
                        sharepointIds = [pscustomobject]@{ siteId = 'site-known' }
                    }
                    [pscustomobject]@{
                        id            = 'contoso-my.sharepoint.com,cccc,dddd'
                        webUrl        = 'https://contoso-my.sharepoint.com/personal/unknown_contoso_com'
                        sharepointIds = [pscustomobject]@{ siteId = 'site-unknown' }
                    }
                )
            }
            if ($Uri -match 'getOneDriveUsageAccountDetail') {
                return @([pscustomobject]@{ siteId = 'site-known'; ownerPrincipalName = 'known@contoso.com' })
            }
            @()
        }

        Set-CIPPDBCacheOneDriveLongPaths -TenantFilter 'contoso.com'

        $script:Orchestrations.Count | Should -Be 1
        $Batch = @($script:Orchestrations[0].Batch)
        $Batch.Count | Should -Be 2
        ($Batch | Where-Object { $_.OwnerPrincipalName -eq 'known@contoso.com' }).Count | Should -Be 1
        ($Batch | Where-Object { $_.SiteId -eq 'contoso-my.sharepoint.com,cccc,dddd' -and [string]::IsNullOrWhiteSpace($_.OwnerPrincipalName) }).Count | Should -Be 1
        $Batch[0].InferredLocalRootFixedLength | Should -Be (('C:\Users\').Length + ('\OneDrive - Contoso\').Length)
        ((Get-FakeTableRows -TableName 'CippOneDriveLongPathsState') | Where-Object { $_.RowKey -eq 'scan' }).Count | Should -Be 1
    }
}

Describe 'Push-DBCacheOneDriveLongPaths' {
    BeforeEach {
        $script:FakeTables = @{}
        $script:Orchestrations = [System.Collections.Generic.List[object]]::new()
        $env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS = '99999'
        Add-CIPPAzDataTableEntity -TableName 'CippOneDriveLongPathsState' -Entity @{
            PartitionKey = 'contoso.com'
            RowKey       = 'scan'
            ScanId       = 'scan-1'
        } -Force
    }

    It 'writes allowlisted counts and resumes from checkpoint with running totals' {
        $LongFolder = ('F' * 200)
        $LongName = ('N' * 80) + '.docx'
        # Cloud length ~281; with local root for known@contoso / Contoso this exceeds 260.

        $script:GraphGetHandler = {
            param($Uri, $SkipValueExtraction)
            if ($Uri -match '/sites/.+/drive\?') {
                return [pscustomobject]@{
                    id        = 'b!drive1'
                    name      = 'Documents'
                    driveType = 'documentLibrary'
                    owner     = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'known@contoso.com' } }
                }
            }
            if ($Uri -match '/root/delta' -and $Uri -notmatch 'token=page2') {
                $Page = [pscustomobject]@{
                    value            = @(
                        [pscustomobject]@{
                            id              = 'item1'
                            name            = $LongName
                            folder          = $null
                            file            = [pscustomobject]@{}
                            parentReference = [pscustomobject]@{ path = "/drives/b!drive1/root:/$LongFolder" }
                        }
                    )
                    '@odata.nextLink' = 'https://graph.microsoft.com/beta/drives/b!drive1/root/delta?token=page2'
                }
                if ($SkipValueExtraction) { return $Page }
                return $Page.value
            }
            if ($Uri -match 'token=page2') {
                $Page = [pscustomobject]@{
                    value             = @(
                        [pscustomobject]@{
                            id              = 'item2'
                            name            = 'short.txt'
                            folder          = $null
                            file            = [pscustomobject]@{}
                            parentReference = [pscustomobject]@{ path = '/drives/b!drive1/root:' }
                        }
                    )
                    '@odata.deltaLink' = 'https://graph.microsoft.com/beta/drives/b!drive1/root/delta?token=done'
                }
                if ($SkipValueExtraction) { return $Page }
                return $Page.value
            }
            @()
        }

        $Item = [pscustomobject]@{
            FunctionName                 = 'DBCacheOneDriveLongPaths'
            TenantFilter                 = 'contoso.com'
            SiteId                       = 'contoso-my.sharepoint.com,aaaa,bbbb'
            OwnerPrincipalName           = 'known@contoso.com'
            OrgDisplayName               = 'Contoso'
            InferredLocalRootFixedLength = ('C:\Users\').Length + ('\OneDrive - Contoso\').Length
            ScanId                       = 'scan-1'
        }

        # Force timebox after first page so resume carries counts.
        $env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS = '0'
        Push-DBCacheOneDriveLongPaths -Item $Item
        $script:Orchestrations.Count | Should -Be 1

        $Chk = (Get-FakeTableRows -TableName 'CippOneDriveLongPathsState') | Where-Object { $_.RowKey -like 'chk-*' } | Select-Object -First 1
        $Chk | Should -Not -BeNullOrEmpty
        $Chk.StateJson | Should -Not -BeNullOrEmpty
        $State = $Chk.StateJson | ConvertFrom-Json
        $State.CountOver260 | Should -BeGreaterThan 0
        $State.PSObject.Properties.Name | Should -Not -Contain 'path'
        $Carried260 = [int]$State.CountOver260

        $env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS = '99999'
        $Resume = $script:Orchestrations[0].Batch[0]
        Push-DBCacheOneDriveLongPaths -Item $Resume

        $CacheRows = Get-FakeTableRows -TableName 'CippReportingDB'
        $CacheRows.Count | Should -Be 1
        $Data = $CacheRows[0].Data | ConvertFrom-Json
        $Data.ownerPrincipalName | Should -Be 'known@contoso.com'
        $Data.countOver260 | Should -Be $Carried260
        $Data.countOver400 | Should -Be 0
        @($Data.PSObject.Properties.Name | Sort-Object) | Should -Be @('countOver260', 'countOver400', 'id', 'ownerPrincipalName')
        $Data.PSObject.Properties.Name | Should -Not -Contain 'webUrl'
        $Data.PSObject.Properties.Name | Should -Not -Contain 'name'
    }

    It 'resolves owner from drive when UPN was not passed' {
        Add-CIPPAzDataTableEntity -TableName 'CippOneDriveLongPathsState' -Entity @{
            PartitionKey = 'contoso.com'
            RowKey       = 'scan'
            ScanId       = 'scan-owner'
        } -Force
        $script:GraphGetHandler = {
            param($Uri, $SkipValueExtraction)
            if ($Uri -match '/sites/.+/drive\?') {
                return [pscustomobject]@{
                    id    = 'b!drive1'
                    name  = 'Documents'
                    owner = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'fromdrive@contoso.com' } }
                }
            }
            if ($Uri -match '/root/delta') {
                $Page = [pscustomobject]@{
                    value              = @()
                    '@odata.deltaLink' = 'https://graph.microsoft.com/beta/drives/b!drive1/root/delta?token=done'
                }
                if ($SkipValueExtraction) { return $Page }
                return @()
            }
            @()
        }

        Push-DBCacheOneDriveLongPaths -Item ([pscustomobject]@{
                TenantFilter                 = 'contoso.com'
                SiteId                       = 'site1'
                OwnerPrincipalName           = ''
                OrgDisplayName               = 'Contoso'
                InferredLocalRootFixedLength = ('C:\Users\').Length + ('\OneDrive - Contoso\').Length
                ScanId                       = 'scan-owner'
            })

        $Data = (Get-FakeTableRows -TableName 'CippReportingDB')[0].Data | ConvertFrom-Json
        $Data.ownerPrincipalName | Should -Be 'fromdrive@contoso.com'
    }

    It 'does not $select webUrl on delta' {
        Add-CIPPAzDataTableEntity -TableName 'CippOneDriveLongPathsState' -Entity @{
            PartitionKey = 'contoso.com'
            RowKey       = 'scan'
            ScanId       = 'scan-2'
        } -Force
        $script:SeenDelta = $null
        $script:GraphGetHandler = {
            param($Uri, $SkipValueExtraction)
            if ($Uri -match '/sites/.+/drive\?') {
                return [pscustomobject]@{
                    id    = 'b!drive1'
                    name  = 'Documents'
                    owner = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'u@contoso.com' } }
                }
            }
            if ($Uri -match '/root/delta') {
                $script:SeenDelta = $Uri
                $Page = [pscustomobject]@{
                    value              = @()
                    '@odata.deltaLink' = 'https://graph.microsoft.com/beta/drives/b!drive1/root/delta?token=done'
                }
                if ($SkipValueExtraction) { return $Page }
                return @()
            }
            @()
        }

        Push-DBCacheOneDriveLongPaths -Item ([pscustomobject]@{
                TenantFilter                 = 'contoso.com'
                SiteId                       = 'site1'
                OwnerPrincipalName           = 'u@contoso.com'
                OrgDisplayName               = 'Contoso'
                InferredLocalRootFixedLength = ('C:\Users\').Length + ('\OneDrive - Contoso\').Length
                ScanId                       = 'scan-2'
            })

        $script:SeenDelta | Should -Match 'parentReference'
        $script:SeenDelta | Should -Not -Match 'webUrl'
    }

    It 'no-ops when ScanId is superseded' {
        $script:GraphGetHandler = { param($Uri, $SkipValueExtraction) throw 'should not call graph' }
        Push-DBCacheOneDriveLongPaths -Item ([pscustomobject]@{
                TenantFilter       = 'contoso.com'
                SiteId             = 'site1'
                OwnerPrincipalName = 'u@contoso.com'
                ScanId             = 'old-scan'
            })
        (Get-FakeTableRows -TableName 'CippReportingDB').Count | Should -Be 0
    }
}
