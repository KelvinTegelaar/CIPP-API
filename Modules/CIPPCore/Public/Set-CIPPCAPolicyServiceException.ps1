function Set-CIPPCAPolicyServiceException {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter,
        $PolicyId
    )

    $CSPtenantId = $env:TenantID

    # Get the current policy
    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)" -tenantid $TenantFilter -AsApp $true

    # If the policy is set to affect either all or all guests/external users
    if ($policy.conditions.users.includeUsers -eq "All" -OR $policy.conditions.users.includeGuestsOrExternalUsers.externalTenants.membershipKind -eq "all") {

        # Check if the policy already has the correct service provider exception
        if ($policy.conditions.users.excludeGuestsOrExternalUsers) {
            $excludeConfig = $policy.conditions.users.excludeGuestsOrExternalUsers

            # Check if serviceProvider is already in guestOrExternalUserTypes
            $hasServiceProvider = $excludeConfig.guestOrExternalUserTypes -match "serviceProvider"

            # Check if externalTenants is properly configured
            if ($excludeConfig.externalTenants) {
                $externalTenants = $excludeConfig.externalTenants
                $hasCorrectExternalTenants = ($externalTenants.membershipKind -eq "enumerated" -and
                                           $externalTenants.members -contains $CSPtenantId)

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
                guestOrExternalUserTypes = "serviceProvider"
                externalTenants = [pscustomobject]@{
                    '@odata.type' = "#microsoft.graph.conditionalAccessEnumeratedExternalTenants"
                    membershipKind = "enumerated"
                    members = @(
                        $CSPtenantId
                    )
                }
            }

            # Add data to cached policy
            $policy.conditions.users.excludeGuestsOrExternalUsers = $excludeServiceProviderData
        }

        # If excludeGuestsOrExternalUsers already has content correct it to match $excludeServiceProviderData
        if ($policy.conditions.users.excludeGuestsOrExternalUsers) {

            # If guestOrExternalUserTypes doesn't include type serviceProvider add it
            if ($policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -notmatch "serviceProvider") {
                $policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes += ",serviceProvider"
            }

            # If guestOrExternalUserTypes includes type serviceProvider and membershipKind is not all tenants
            if ($policy.conditions.users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -match "serviceProvider" -AND $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.membershipKind -ne "all") {

                # If membershipKind is enumerated and members does not include our tenant add it
                if ($policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.membershipKind -eq "enumerated" -AND $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members -notmatch $CSPtenantId) {
                    $policy.conditions.users.excludeGuestsOrExternalUsers.externalTenants.members += $($CSPtenantId)
                }
            }
        }

    }

    # Patch policy with updated data.
    # TemplateId,createdDateTime,modifiedDateTime can't be written back so exclude them using -ExcludeProperty
    if ($PSCmdlet.ShouldProcess($PolicyId, "Update policy with service provider exception")) {
        $patch = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($policy.id)" -tenantid $TenantFilter -type PATCH -body ($policy | Select-Object * -ExcludeProperty TemplateId,createdDateTime,modifiedDateTime | ConvertTo-Json -Depth 20) -AsApp $true
        return "Successfully added service provider to policy $PolicyId"
    }

}
