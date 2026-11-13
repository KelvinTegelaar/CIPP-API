# The service-provider exclusion must name the partner tenant that holds the customer's GDAP
# relationship. A customer owned by a secondary partner would otherwise exclude the primary
# and keep blocking CIPP's delegated sign-ins.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Set-CIPPCAPolicyServiceException.ps1')

    function New-GraphGETRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Resolve-CIPPOwningPartner { param($TenantFilter) }
}

Describe 'Set-CIPPCAPolicyServiceException' {
    BeforeEach {
        $env:TenantID = 'primary-partner'
        $script:Patched = $null
        Mock Resolve-CIPPOwningPartner { 'secondary-partner' }
        Mock New-GraphPOSTRequest { $script:Patched = $body | ConvertFrom-Json }
    }

    It 'adds the owning partner when the policy has no exclusion' {
        Mock New-GraphGETRequest {
            [pscustomobject]@{ id = 'p1'; conditions = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All'); excludeGuestsOrExternalUsers = $null } } }
        }

        $Result = Set-CIPPCAPolicyServiceException -TenantFilter 'customer.onmicrosoft.com' -PolicyId 'p1'

        Should -Invoke Resolve-CIPPOwningPartner -Times 1 -ParameterFilter { $TenantFilter -eq 'customer.onmicrosoft.com' }
        $Result | Should -Match 'Successfully'
        $script:Patched.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members | Should -Be @('secondary-partner')
    }

    It 'appends the owning partner to an enumerated list that only names the primary' {
        Mock New-GraphGETRequest {
            [pscustomobject]@{ id = 'p1'; conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        includeUsers                 = @('All')
                        excludeGuestsOrExternalUsers = [pscustomobject]@{
                            guestOrExternalUserTypes = 'serviceProvider'
                            externalTenants          = [pscustomobject]@{ membershipKind = 'enumerated'; members = @('primary-partner') }
                        }
                    } } }
        }

        $null = Set-CIPPCAPolicyServiceException -TenantFilter 'customer.onmicrosoft.com' -PolicyId 'p1'

        $script:Patched.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members | Should -Be @('primary-partner', 'secondary-partner')
    }

    It 'makes no change when the owning partner is already excluded' {
        Mock New-GraphGETRequest {
            [pscustomobject]@{ id = 'p1'; conditions = [pscustomobject]@{ users = [pscustomobject]@{
                        includeUsers                 = @('All')
                        excludeGuestsOrExternalUsers = [pscustomobject]@{
                            guestOrExternalUserTypes = 'serviceProvider'
                            externalTenants          = [pscustomobject]@{ membershipKind = 'enumerated'; members = @('secondary-partner') }
                        }
                    } } }
        }

        $Result = Set-CIPPCAPolicyServiceException -TenantFilter 'customer.onmicrosoft.com' -PolicyId 'p1'

        $Result | Should -Match 'No changes needed'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}
