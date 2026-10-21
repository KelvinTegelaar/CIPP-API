# Pester tests for Set-CIPPDBCacheIntuneAppProtectionPolicies: a successful collection is authoritative, so an
# empty result clears the previous rows, while a failed sub-request writes nothing and keeps them.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntuneAppProtectionPolicies.ps1')

    function Test-CIPPStandardLicense { $true }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Add-CIPPDbItem {
        param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        $script:Written[$Type] = [pscustomobject]@{ Count = @($Data).Count; ClearOnEmpty = $ClearOnEmpty.IsPresent }
    }
    function New-GraphBulkRequest {
        param($Requests, $tenantid)
        foreach ($Request in @($Requests)) {
            $Status = if ($Request.id -eq $script:FailId) { 500 } else { 200 }
            [pscustomobject]@{ id = $Request.id; status = $Status; body = [pscustomobject]@{ value = @() } }
        }
    }
}

Describe 'Set-CIPPDBCacheIntuneAppProtectionPolicies' {
    BeforeEach {
        $script:Written = @{}
        $script:FailId = $null
    }

    It 'clears every type when the tenant has no app protection policies left' {
        Set-CIPPDBCacheIntuneAppProtectionPolicies -TenantFilter 'contoso.com'
        foreach ($Type in 'IntuneAppProtectionPolicyGroups', 'IntuneAppProtectionManagedAppPolicies', 'IntuneAppProtectionMobileAppConfigurations') {
            $script:Written[$Type].Count | Should -Be 0
            $script:Written[$Type].ClearOnEmpty | Should -BeTrue
        }
    }

    It 'writes nothing when a sub-request fails' {
        $script:FailId = 'ManagedAppPolicies'
        Set-CIPPDBCacheIntuneAppProtectionPolicies -TenantFilter 'contoso.com'
        $script:Written.Count | Should -Be 0
    }
}
