# The SPOSites collector streams the tenant-wide enumeration in chunks: each chunk gets one authoritative
# per-site read and is written before the next, so a very large tenant is never held whole.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPSPOSite { param($TenantFilter, [switch]$UseCertificate, [string[]]$Properties) }
    function Get-CIPPSPOSiteBulk { param($TenantFilter, $SiteUrls, $MaxConcurrency, $BatchSize, $Properties, [switch]$UseCertificate) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem {
        param($TenantFilter, $Type, [Parameter(ValueFromPipeline)][Alias('Data')]$InputObject, [switch]$AddCount, [switch]$ClearOnEmpty)
        process { $script:Written.Add($InputObject) }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSPOSites.ps1')

    function New-Site { param($i) [PSCustomObject]@{ SiteId = "id$i"; Url = "https://contoso.sharepoint.com/sites/s$i"; Title = "Site $i"; GroupId = [guid]::Empty; OwnerEmail = ''; SharingCapability = 1 } }
}

Describe 'Set-CIPPDBCacheSPOSites' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPSPOSite { foreach ($i in 1..1203) { New-Site $i } }
        Mock Write-LogMessage {}
    }

    It 'reads and writes every site in chunks, overlaying the authoritative per-site values' {
        Mock Get-CIPPSPOSiteBulk {
            foreach ($Url in $SiteUrls) {
                if ($Url -like '*/s7') { [PSCustomObject]@{ SiteUrl = $Url; Success = $false; Site = $null } }
                else { [PSCustomObject]@{ SiteUrl = $Url; Success = $true; Site = [PSCustomObject]@{ OwnerEmail = 'owner@contoso.com' } } }
            }
        }

        Set-CIPPDBCacheSPOSites -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Get-CIPPSPOSiteBulk -Times 3 -Exactly
        Should -Invoke Get-CIPPSPOSiteBulk -ParameterFilter { $SiteUrls.Count -gt 500 } -Times 0 -Exactly
        Should -Invoke Get-CIPPSPOSite -ParameterFilter { $Properties -contains 'SiteId' -and $Properties -contains 'OwnerEmail' } -Times 1 -Exactly
        $script:Written.Count | Should -Be 1203
        @($script:Written[0].PSObject.Properties.Name)[0..2] | Should -Be @('id', 'Url', 'Title')
        $script:Written[0].GroupId | Should -Be ([guid]::Empty.ToString())
        $script:Written[0].OwnerEmail | Should -Be 'owner@contoso.com'
        $script:Written[6].OwnerEmail | Should -Be ''
    }

    It 'falls back to the enumeration values when the per-site read fails' {
        Mock Get-CIPPSPOSiteBulk { throw 'too many resources' }

        Set-CIPPDBCacheSPOSites -TenantFilter 'contoso.onmicrosoft.com'

        $script:Written.Count | Should -Be 1203
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1203 of 1203*too many resources' } -Times 1 -Exactly
    }
}
