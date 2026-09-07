# Regression tests for the tenant-group authorization gap in Test-CIPPAccess.
#
# A requested tenant GROUP ({type:'Group', value:<guid>}) used to resolve to a null $Tenant and fall
# through to an unconditional allow, so a restricted role could target a group it was never granted.
# The fix authorizes a group request by group identity: allow iff the requested group GUID is one of
# the role's granted group entries; otherwise hard-deny. Members are never expanded for the decision.
#
# Driven through the APIClient path (aad idp + GUID principal name), which skips the user/impersonation
# branch and reaches the per-endpoint permission evaluation with a restricted role.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'
    $FunctionPath = Join-Path $AuthDir 'Test-CIPPAccess.ps1'
    $ScopeHelperPath = Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1'

    # Stubs for the surface the APIClient path touches.
    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CIPPRolePermissions { param($Role) }
    function Get-Tenants { param([switch]$IncludeErrors) @() }
    function Get-CippAccessScopeRule { param($Role) }
    function Expand-CIPPTenantGroups { param($TenantFilter) @() }

    . $ScopeHelperPath
    . $FunctionPath

    # Bypass the config-file reads by pre-seeding the runspace caches the function guards on.
    $script:CIPPFunctionPermissions = @{
        'Invoke-AddScheduledItem' = @{ Role = 'CIPP.Scheduler.ReadWrite'; Functionality = 'Entrypoint' }
    }
    $script:CIPPBaseRoles = [pscustomobject]@{}

    # A request from an API client, scoped by a restricted custom role, asking to act on a group.
    function New-GroupRequest {
        param([string]$RequestedGroupId)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddScheduledItem' }
            Headers = @{
                'x-ms-client-principal-idp'  = 'aad'
                'x-ms-client-principal-name' = '11111111-1111-1111-1111-111111111111'
                'x-forwarded-for'            = '1.2.3.4'
            }
            Query   = @{}
            Body    = @{ tenantFilter = [pscustomobject]@{ type = 'Group'; value = $RequestedGroupId; label = 'Requested Group' } }
        }
    }

    # The restricted role grants exactly one group ('group-allowed') and nothing else.
    function Set-RestrictedRoleMocks {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('grouprole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{
                Role             = 'grouprole'
                Permissions      = @('CIPP.Scheduler.ReadWrite')
                AllowedTenants   = @([pscustomobject]@{ type = 'Group'; value = 'group-allowed'; label = 'Allowed Group' })
                BlockedTenants   = @()
                BlockedEndpoints = @()
            }
        }
        Mock -CommandName Get-Tenants -MockWith { @() }
    }
}

Describe 'Test-CIPPAccess tenant-group authorization' {
    BeforeEach { Set-RestrictedRoleMocks }

    It 'allows a request for a group the role was granted' {
        $result = Test-CIPPAccess -Request (New-GroupRequest -RequestedGroupId 'group-allowed')
        $result | Should -BeTrue
    }

    It 'denies a request for a group the role was NOT granted' {
        { Test-CIPPAccess -Request (New-GroupRequest -RequestedGroupId 'group-notgranted') } |
            Should -Throw -ExpectedMessage '*not allowed*'
    }

    It 'authorizes by group identity, never by expanding members' {
        # If the decision expanded members it would have to call Expand-CIPPTenantGroups; it must not.
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { throw 'membership must not be expanded for the access decision' }
        $result = Test-CIPPAccess -Request (New-GroupRequest -RequestedGroupId 'group-allowed')
        $result | Should -BeTrue
        Should -Invoke -CommandName Expand-CIPPTenantGroups -Times 0
    }
}
