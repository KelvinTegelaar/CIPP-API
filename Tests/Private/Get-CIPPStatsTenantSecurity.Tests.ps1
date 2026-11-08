# Pester tests for Get-CIPPStatsTenantSecurity: capability counts from the CacheCapabilities table and
# CA / Security Defaults posture buckets from the cached CA counts and SecurityDefaults rows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CippJson' -as [type])) { Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$ByTenant) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPStatsTenantSecurity.ps1')

    function New-CapabilityRow($RowKey, [string[]]$Plans, [string[]]$DisabledPlans = @()) {
        $ServicePlans = @(
            foreach ($Plan in $Plans) { @{ servicePlanName = $Plan; provisioningStatus = 'Success' } }
            foreach ($Plan in $DisabledPlans) { @{ servicePlanName = $Plan; provisioningStatus = 'disabled' } }
        )
        [pscustomobject]@{ RowKey = $RowKey; JSON = (@(@{ skuId = 'x'; servicePlans = $ServicePlans }) | ConvertTo-Json -Compress -Depth 5) }
    }
    function New-CountRow($Domain, $Count) { [pscustomobject]@{ PartitionKey = $Domain; RowKey = 'ConditionalAccessPolicies-Count'; DataCount = $Count } }
    function New-SecurityDefaultsRow($Enabled) { [pscustomobject]@{ Data = (@{ id = 'p'; isEnabled = $Enabled } | ConvertTo-Json -Compress) } }
}

Describe 'Get-CIPPStatsTenantSecurity' {
    BeforeEach {
        $script:Tenants = @(
            [pscustomobject]@{ defaultDomainName = 'p1-with-ca.com'; customerId = '00000000-0000-0000-0000-000000000001'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges' }
            [pscustomobject]@{ defaultDomainName = 'p2-no-ca.com'; customerId = '00000000-0000-0000-0000-000000000002'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges' }
            [pscustomobject]@{ defaultDomainName = 'sd-on.com'; customerId = '00000000-0000-0000-0000-000000000003'; delegatedPrivilegeStatus = 'directTenant' }
            [pscustomobject]@{ defaultDomainName = 'sd-off.com'; customerId = '00000000-0000-0000-0000-000000000004'; delegatedPrivilegeStatus = 'directTenant' }
            [pscustomobject]@{ defaultDomainName = 'no-cache.com'; customerId = '00000000-0000-0000-0000-000000000005'; delegatedPrivilegeStatus = 'directTenant' }
        )
        Mock Get-CIPPAzDataTableEntity {
            @(
                (New-CapabilityRow 'p1-with-ca.com' @('AAD_PREMIUM', 'EXCHANGE_S_STANDARD', 'INTUNE_A'))
                # keyed by customer GUID, with P2 disabled so only P1 counts
                (New-CapabilityRow '00000000-0000-0000-0000-000000000002' @('AAD_PREMIUM', 'EXCHANGE_S_ENTERPRISE') @('AAD_PREMIUM_P2'))
                (New-CapabilityRow 'sd-on.com' @('EXCHANGE_S_STANDARD', 'SHAREPOINTSTANDARD'))
                (New-CapabilityRow 'sd-off.com' @('EXCHANGE_S_STANDARD'))
                (New-CapabilityRow 'unmanaged.com' @('AAD_PREMIUM_P2'))
            )
        }
        Mock Get-CIPPDbItem {
            $Rows = [ordered]@{}
            $Rows['sd-on.com'] = @((New-SecurityDefaultsRow $true))
            $Rows['sd-off.com'] = @((New-SecurityDefaultsRow $false))
            $Rows
        }
        $script:CACounts = @((New-CountRow 'p1-with-ca.com' 4), (New-CountRow 'p2-no-ca.com' 0), (New-CountRow 'sd-on.com' 0))
    }

    It 'counts tenants per capability using enabled plans only, ignoring tenants that are not managed' {
        $r = Get-CIPPStatsTenantSecurity -Tenants $script:Tenants -CACounts $script:CACounts
        $r.TenantCapabilities.Exchange | Should -Be 4
        $r.TenantCapabilities.Entra | Should -Be 2
        $r.TenantCapabilities.EntraP2 | Should -Be 0
        $r.TenantCapabilities.Intune | Should -Be 1
        $r.TenantCapabilities.SharePoint | Should -Be 1
        $r.TenantCapabilities.Teams | Should -Be 0
    }

    It 'buckets every tenant once by CA licensing, CA policies and Security Defaults' {
        $r = Get-CIPPStatsTenantSecurity -Tenants $script:Tenants -CACounts $script:CACounts
        $r.SecuritySettings.CALicensedWithPolicies | Should -Be 1
        $r.SecuritySettings.CALicensedNoPolicies | Should -Be 1
        $r.SecuritySettings.NotLicensedSecurityDefaultsEnabled | Should -Be 1
        $r.SecuritySettings.NotLicensedSecurityDefaultsDisabled | Should -Be 1
        $r.SecuritySettings.Unknown | Should -Be 1
        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter { $TenantFilter -eq 'allTenants' -and $Type -eq 'SecurityDefaults' -and $ByTenant }
    }

    It 'marks a licensed tenant without a cached CA count as unknown' {
        $r = Get-CIPPStatsTenantSecurity -Tenants $script:Tenants -CACounts @()
        $r.SecuritySettings.CALicensedWithPolicies | Should -Be 0
        $r.SecuritySettings.CALicensedNoPolicies | Should -Be 0
        $r.SecuritySettings.Unknown | Should -Be 3
    }

    It 'returns nulls when the table read fails' {
        Mock Get-CIPPAzDataTableEntity { throw 'boom' }
        $r = Get-CIPPStatsTenantSecurity -Tenants $script:Tenants -CACounts $script:CACounts
        $r.TenantCapabilities | Should -BeNullOrEmpty
        $r.SecuritySettings | Should -BeNullOrEmpty
    }
}
