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
        if ($uri -notmatch '/site/RecycleBin\?') { return @() }
        $Skip = if ($uri -match '\$skip=(\d+)') { [int]$Matches[1] } else { 0 }
        $Top = if ($uri -match '\$top=(\d+)') { [int]$Matches[1] } else { 100 }
        [PSCustomObject]@{ value = @($script:Bin | Select-Object -Skip $Skip -First $Top) }
    }

    . $FunctionPath
}

Describe 'Push-DBCacheStorageCleanupScanBatch' {
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
