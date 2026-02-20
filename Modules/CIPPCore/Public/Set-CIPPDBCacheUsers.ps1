function Set-CIPPDBCacheUsers {
    <#
    .SYNOPSIS
        Caches all users for a tenant

    .PARAMETER TenantFilter
        The tenant to cache users for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching users' -sev Debug

        $SignInLogsCapable = Test-CIPPStandardLicense -StandardName 'UserSignInLogsCapable' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog

        # Base properties needed by tests, standards, reports, UI, and integrations (Hudu, NinjaOne)
        $BaseSelect = @(
            # Core identity
            'id'
            'displayName'
            'userPrincipalName'
            'givenName'
            'surname'
            'mailNickname'

            # Account status
            'accountEnabled'
            'userType'
            'isResourceAccount'
            'createdDateTime'

            # Security & policies
            'passwordPolicies'
            'perUserMfaState'

            # Contact information
            'mail'
            'otherMails'
            'mobilePhone'
            'businessPhones'
            'faxNumber'
            'proxyAddresses'

            # Location & organization
            'jobTitle'
            'department'
            'companyName'
            'officeLocation'
            'city'
            'state'
            'country'
            'postalCode'
            'streetAddress'

            # Settings
            'preferredLanguage'
            'usageLocation'
            'preferredDataLocation'
            'showInAddressList'

            # Licenses
            'assignedLicenses'
            'assignedPlans'
            'licenseAssignmentStates'

            # On-premises sync
            'onPremisesSyncEnabled'
            'onPremisesImmutableId'
            'onPremisesLastSyncDateTime'
            'onPremisesDistinguishedName'
        )

        if ($SignInLogsCapable) {
            $Select = ($BaseSelect + 'signInActivity') -join ','
            $Top = 500
        } else {
            $Select = $BaseSelect -join ','
            $Top = 999
        }

        # Stream users directly from Graph API to batch processor
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=$Top&`$select=$Select&`$count=true" -ComplexFilter -tenantid $TenantFilter |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached users successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache users: $($_.Exception.Message)" -sev Error
    }
}
