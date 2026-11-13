BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-DBCacheStorageCleanupScanBatch.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com' } }
    function New-GraphGetRequest {
        param(
            $uri, $tenantid, $scope, $AsApp, $extraHeaders,
            [switch]$UseCertificate,
            [bool]$noPagination,
            [switch]$SkipValueExtraction
        )
        if ($uri -match '^https://graph\.microsoft\.com/beta/sites/.+/lists\?') { return $script:Lists }
        if ($uri -match "/_api/web/lists\(guid'([^']+)'\)\?") { return $script:ListInfo[$Matches[1]] }
        if ($uri -notmatch '/site/RecycleBin\?') { return @() }
        $Skip = if ($uri -match '\$skip=(\d+)') { [int]$Matches[1] } else { 0 }
        $Top = if ($uri -match '\$top=(\d+)') { [int]$Matches[1] } else { 100 }
        [PSCustomObject]@{ value = @($script:Bin | Select-Object -Skip $Skip -First $Top) }
    }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-SPOAdminListInt64.ps1')
}

Describe 'Push-DBCacheStorageCleanupScanBatch' {
    AfterEach { $script:Lists = $null; $script:ListInfo = $null; $script:Bin = $null }

    It 'records each library''s version policy from its trim mode' {
        $script:Lists = @('off', 'none', 'age', 'auto', 'empty', 'meta') | ForEach-Object { [PSCustomObject]@{ id = $_; name = $_; displayName = $_; list = [PSCustomObject]@{ template = 'documentLibrary' } } }
        $Metrics = [PSCustomObject]@{ StorageMetrics = [PSCustomObject]@{ TotalSize = '10000000'; TotalFileStreamSize = '1000000'; TotalFileCount = '100' } }
        $script:ListInfo = @{
            off  = [PSCustomObject]@{ EnableVersioning = $false; MajorVersionLimit = 0; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 0 }; RootFolder = $Metrics }
            none = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 0 }; RootFolder = $Metrics }
            age  = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 100; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 1; DefaultExpireAfterDays = 365 }; RootFolder = $Metrics }
            auto = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 2; DefaultExpireAfterDays = 30 }; RootFolder = $Metrics }
            empty = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 2 }; RootFolder = [PSCustomObject]@{ StorageMetrics = [PSCustomObject]@{ TotalSize = '40272'; TotalFileStreamSize = '0'; TotalFileCount = '0' } } }
            # Measured on 7ngn50: 25,000 tiny files with no versions, all of the difference is metadata.
            meta  = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 2 }; RootFolder = [PSCustomObject]@{ StorageMetrics = [PSCustomObject]@{ TotalSize = '8852859'; TotalFileStreamSize = '963894'; TotalFileCount = '25000' } } }
        }
        $Result = Push-DBCacheStorageCleanupScanBatch -Item @{
            TenantFilter = 'contoso.onmicrosoft.com'
            BatchNumber  = 1
            Sites        = @(@{ id = 's1'; displayName = 'A'; webUrl = 'https://contoso.sharepoint.com/sites/a' })
        }

        $Rows = @{}
        foreach ($Row in $Result.Sites[0].Rows) { $Rows[$Row.libraryId] = $Row }
        $Rows.off.versionPolicy | Should -Be 'Versioning off'
        $Rows.none.versionPolicy | Should -Be '500 versions, never expire'
        $Rows.age.versionPolicy | Should -Be '100 versions, expire after 365 days'
        $Rows.auto.versionPolicy | Should -Be 'Automatic'
        $Rows.none.versionTrimMode | Should -Be 0
        $Rows.none.versionEstimateBytes | Should -Be (9000000 - 40KB - 320 * 100)
        $Rows.none.fileStreamSizeInBytes | Should -Be 1000000
        $Rows.empty.versionEstimateBytes | Should -Be 0
        $Rows.meta.versionEstimateBytes | Should -Be 0
    }

    It 'counts every recycle bin item of a bin larger than one page' {
        $script:Bin = @(1..520 | ForEach-Object { [PSCustomObject]@{ Id = "$_"; Size = 10; ItemState = 1 } })
        $Result = Push-DBCacheStorageCleanupScanBatch -Item @{
            TenantFilter = 'contoso.onmicrosoft.com'
            BatchNumber  = 1
            Sites        = @(@{ id = 's1'; displayName = 'A'; webUrl = 'https://contoso.sharepoint.com/sites/a' })
        }

        $Row = $Result.Sites[0].SiteRow
        $Result.Sites[0].CollectionStatus | Should -Be 'Full'
        $Row.recycleItemCount | Should -Be 520
        $Row.recycleTotalBytes | Should -Be 5200
        $Row.recycleScannedItems | Should -Be 520
        $Row.recycleCapped | Should -BeFalse
    }
}
