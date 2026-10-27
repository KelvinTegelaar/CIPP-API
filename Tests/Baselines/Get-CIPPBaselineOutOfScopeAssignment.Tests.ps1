BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-TenantGroups { }
    function Get-CIPPTenantLookup { }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineOutOfScopeAssignment.ps1')

    $script:Assignments = @(
        [pscustomobject]@{ label = 'Contoso'; value = 'contoso.com' }
        [pscustomobject]@{ label = 'EU customers'; value = 'group-eu' }
        'fabrikam.com'
        [pscustomobject]@{ label = 'Exported Template'; value = 'Exported Template' }
    )
}

Describe 'Get-CIPPBaselineOutOfScopeAssignment' {
    BeforeEach {
        Mock Get-TenantGroups { [pscustomobject]@{ Id = 'group-eu'; Name = 'EU customers' } }
        Mock Get-CIPPTenantLookup {
            @{
                'contoso.com'  = [pscustomobject]@{ customerId = 'cust-contoso' }
                'fabrikam.com' = [pscustomobject]@{ customerId = 'cust-fabrikam' }
            }
        }
    }

    It 'returns nothing for an unrestricted caller' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = $null }
        @(Get-CIPPBaselineOutOfScopeAssignment -Assignments ($script:Assignments + 'AllTenants')) | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPTenantLookup -Times 0
    }

    It 'returns the tenants and groups the role does not allow' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('cust-contoso') }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = @() }
        Get-CIPPBaselineOutOfScopeAssignment -Assignments $script:Assignments | Should -Be @('EU customers', 'fabrikam.com')
    }

    It 'allows a group the role grants, and denies AllTenants and unknown tenants' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('cust-contoso', 'cust-fabrikam') }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = @('group-eu') }
        Get-CIPPBaselineOutOfScopeAssignment -Assignments ($script:Assignments + 'AllTenants' + 'unknown.com') | Should -Be @('AllTenants', 'unknown.com')
    }

    It 'denies everything to a role entitled to no tenants' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @() }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = @() }
        @(Get-CIPPBaselineOutOfScopeAssignment -Assignments $script:Assignments).Count | Should -Be 3
    }
}
