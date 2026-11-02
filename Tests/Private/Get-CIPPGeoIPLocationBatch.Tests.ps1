BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec) }
    function Write-LogMessage { param($API, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPGeoIPLocationBatch.ps1')
}

Describe 'Get-CIPPGeoIPLocationBatch' {
    BeforeEach {
        $script:GeoIpMemo = $null
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Add-AzDataTableEntity { }
    }

    It 'keeps the registered owner when no network announces the range, and caches it' {
        Mock Get-CIPPAzDataTableEntity { }
        Mock Invoke-CIPPRestMethod { @([pscustomobject]@{ query = '2603:10a6:102:488::5'; status = 'success'; countryCode = 'CA'; city = 'Toronto'; hosting = $true; proxy = $false; asname = ''; org = 'Microsoft Corporation'; isp = 'Microsoft Corporation' }) }
        $Geo = Get-CIPPGeoIPLocationBatch -IPs @('2603:10a6:102:488::5')
        $Geo['2603:10a6:102:488::5'].ASName | Should -Be 'Unknown'
        $Geo['2603:10a6:102:488::5'].Org | Should -Be 'Microsoft Corporation'
        @($script:Written)[0].Org | Should -Be 'Microsoft Corporation'
    }

    It 're-reads a cached row with no network name from before the owner was kept, but not one with it' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ CountryOrRegion = 'CA'; City = 'Toronto'; Proxy = 'False'; Hosting = 'True'; ASName = 'Unknown' } }
        Mock Invoke-CIPPRestMethod { @([pscustomobject]@{ query = '2603:10a6:102:488::5'; status = 'success'; countryCode = 'CA'; city = 'Toronto'; asname = ''; org = 'Microsoft Corporation' }) }
        (Get-CIPPGeoIPLocationBatch -IPs @('2603:10a6:102:488::5'))['2603:10a6:102:488::5'].Org | Should -Be 'Microsoft Corporation'
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly

        $script:GeoIpMemo = $null
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ CountryOrRegion = 'CA'; City = 'Toronto'; Proxy = 'False'; Hosting = 'True'; ASName = 'Unknown'; Org = 'Microsoft Corporation' } }
        (Get-CIPPGeoIPLocationBatch -IPs @('2603:10a6:102:488::5'))['2603:10a6:102:488::5'].Org | Should -Be 'Microsoft Corporation'
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -Because 'the second row is a cache hit'
    }
}
