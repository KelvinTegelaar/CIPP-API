BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $TimeoutSec) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPAzureCloudRanges.ps1')
    $script:Page = '<a href="https://download.microsoft.com/download/7/1/d/abc/ServiceTags_Public_20260921.json">Download</a>'
    # the download is octet-stream text with a byte order mark
    $script:File = [char]0xFEFF + '{"values":[{"name":"AzureCloud.westeurope","properties":{"addressPrefixes":["20.50.0.0/16"]}},{"name":"AzureCloud","properties":{"addressPrefixes":["20.0.0.0/8","2603:1030::/32"]}}]}'
}

Describe 'Get-CIPPAzureCloudRanges' {
    BeforeEach {
        $script:AzureCloudRanges = $null
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Invoke-CIPPRestMethod { if ($Uri -like '*details.aspx*') { $script:Page } else { $script:File } }
    }

    It 'follows the download page to the weekly file and keeps only the AzureCloud ranges' {
        Mock Get-CIPPAzDataTableEntity { }
        Get-CIPPAzureCloudRanges | Should -Be @('20.0.0.0/8', '2603:1030::/32')
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://download.microsoft.com/download/7/1/d/abc/ServiceTags_Public_20260921.json' }
        $script:Written.RowKey | Should -Be 'AzureCloud'
        @($script:Written.JSON | ConvertFrom-Json) | Should -Be @('20.0.0.0/8', '2603:1030::/32')
    }

    It 'uses a copy under a week old without downloading' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = '["13.64.0.0/11"]'; Timestamp = [datetimeoffset]::UtcNow.AddDays(-6) } }
        Get-CIPPAzureCloudRanges | Should -Be @('13.64.0.0/11')
        Should -Invoke Invoke-CIPPRestMethod -Times 0
    }

    It 'refreshes a week-old copy, and falls back to it when the download fails' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = '["13.64.0.0/11"]'; Timestamp = [datetimeoffset]::UtcNow.AddDays(-8) } }
        Get-CIPPAzureCloudRanges | Should -Be @('20.0.0.0/8', '2603:1030::/32')

        $script:AzureCloudRanges = $null
        Mock Invoke-CIPPRestMethod { '<html>no link here</html>' }
        Get-CIPPAzureCloudRanges | Should -Be @('13.64.0.0/11')
        $script:AzureCloudRanges.Expires | Should -BeLessThan ([datetime]::UtcNow.AddMinutes(15)) -Because 'a stale copy is retried soon'
    }

    It 'throws when there is neither a list nor a cached copy' {
        Mock Get-CIPPAzDataTableEntity { }
        Mock Invoke-CIPPRestMethod { throw 'download.microsoft.com unreachable' }
        { Get-CIPPAzureCloudRanges } | Should -Throw '*unreachable*'
    }
}
