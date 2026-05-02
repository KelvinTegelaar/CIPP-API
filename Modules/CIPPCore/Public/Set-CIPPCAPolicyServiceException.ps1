function Set-CIPPCAPolicyServiceException {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $PolicyId
    )

    if ([string]::IsNullOrWhiteSpace($env:TenantID)) {
        throw 'Environment variable TenantID is not set. Cannot configure service provider exception without the CSP tenant ID.'
    }

    # Get the current policy
    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter -AsApp $true

    # If the policy is set to affect all users, all guests/external users, or specific directory roles
    if ($policy.conditions.users.includeUsers -eq 'All' -or $policy.conditions.users.includeGuestsOrExternalUsers.externalTenants.membershipKind -eq 'all' -or $policy.conditions.users.includeRoles.Count -gt 0) {

        # Check if the policy already has the correct service provider exception
        if ($policy.conditions.users.excludeGuestsOrExternalUsers) {
            $excludeConfig = $policy.conditions.users.excludeGuestsOrExternalUsers

            # Check if serviceProvider is already in guestOrExternalUserTypes
            $hasServiceProvider = $excludeConfig.guestOrExternalUserTypes -match 'serviceProvider'

            # Check if externalTenants is properly configured
            if ($excludeConfig.externalTenants) {
                $externalTenants = $excludeConfig.externalTenants
                $hasCorrectExternalTenants = $externalTenants.membershipKind -eq 'all' -or
                    ($externalTenants.membershipKind -eq 'enumerated' -and
                    $externalTenants.members -contains $env:TenantID)

                # If already configured, exit without making changes
                if ($hasServiceProvider -and $hasCorrectExternalTenants) {
                    return "Policy $PolicyId already has the correct service provider configuration. No changes needed."
                }
            }
        }

        # If excludeGuestsOrExternalUsers is empty, add the entire exclusion
        if (!($policy.conditions.users.excludeGuestsOrExternalUsers)) {

            # Define data
            $excludeServiceProviderData = [pscustomobject]@{
                guestOrExternalUserTypes = 'serviceProvider'
                externalTenants          = [pscustomobject]@{
                    '@odata.type'  = '#microsoft.graph.conditionalAccessEnumeratedExternalTenants'
                    membershipKind = 'enumerated'
                    members        = @(
                        $env:TenantID
                    )
                }
            }

            # Add data to cached policy
            $policy.conditions.users.excludeGuestsOrExternalUsers = $excludeServiceProviderData
        } else {
            # If excludeGuestsOrExternalUsers already has content correct it to match $excludeServiceProviderData

            # If guestOrExternalUserTypes doesn't include type serviceProvider add it
            if ($policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -notmatch 'serviceProvider') {
                $policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes += ',serviceProvider'
            }

            # If guestOrExternalUserTypes includes type serviceProvider and membershipKind is not all tenants
            if ($policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -match 'serviceProvider' -and $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.membershipKind -ne 'all') {

                if (-not $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants) {
                    # externalTenants is missing entirely — create the full structure
                    $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants = [pscustomobject]@{
                        '@odata.type'  = '#microsoft.graph.conditionalAccessEnumeratedExternalTenants'
                        membershipKind = 'enumerated'
                        members        = @($env:TenantID)
                    }
                } elseif ($policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.membershipKind -eq 'enumerated' -and $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members -notcontains $env:TenantID) {
                    $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members += $($env:TenantID)
                }
            }
        }
        $PatchBody = @{
            conditions = @{
                users = $policy.conditions.users
            }
        } | ConvertTo-Json -Depth 20

        Write-Information 'Updated policy JSON:'
        Write-Information $PatchBody

        if ($PSCmdlet.ShouldProcess($PolicyId, 'Update policy with service provider exception')) {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($policy.id)" -tenantid $TenantFilter -type PATCH -body $PatchBody -AsApp $true
            return "Successfully added service provider to policy $PolicyId"
        }
    } else {
        return "Policy $PolicyId does not target all users or all guest/external users. No changes made."
    }
}
