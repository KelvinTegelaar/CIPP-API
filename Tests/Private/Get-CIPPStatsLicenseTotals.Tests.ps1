# Pester tests for Get-CIPPStatsLicenseTotals: purchased totals summed per pretty name across cached LicenseOverview rows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CippJson' -as [type])) { Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$ByTenant) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPStatsLicenseTotals.ps1')

    function New-Row($Object) { [pscustomobject]@{ Data = ($Object | ConvertTo-Json -Compress) } }
}

Describe 'Get-CIPPStatsLicenseTotals' {
    It 'sums TotalLicenses per license name across tenants' {
        Mock Get-CIPPDbItem {
            $Rows = [ordered]@{}
            $Rows['t1.com'] = @(
                (New-Row @{ License = 'Microsoft 365 Business Premium'; TotalLicenses = '1'; skuId = 'a' })
                (New-Row @{ License = 'Exchange Online (Plan 1)'; TotalLicenses = '3'; skuId = 'b' })
            )
            $Rows['t2.com'] = @(
                (New-Row @{ License = 'Microsoft 365 Business Premium'; TotalLicenses = '4'; skuId = 'a' })
                (New-Row @{ License = ''; TotalLicenses = '9'; skuId = 'c' })
                (New-Row @{ License = 'Broken'; TotalLicenses = 'n/a'; skuId = 'd' })
            )
            $Rows
        }
        $r = Get-CIPPStatsLicenseTotals
        $r['Microsoft 365 Business Premium'] | Should -Be 5
        $r['Exchange Online (Plan 1)'] | Should -Be 3
        $r.Keys.Count | Should -Be 2
        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' -and $Type -eq 'LicenseOverview' -and $ByTenant }
    }

    It 'returns an empty map when the read fails' {
        Mock Get-CIPPDbItem { throw 'boom' }
        $r = Get-CIPPStatsLicenseTotals
        $r.Keys.Count | Should -Be 0
    }
}
