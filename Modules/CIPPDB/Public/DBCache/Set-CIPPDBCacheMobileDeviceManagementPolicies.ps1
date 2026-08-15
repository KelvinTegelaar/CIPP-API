function Set-CIPPDBCacheMobileDeviceManagementPolicies {
    <#
    .SYNOPSIS
        Caches the Microsoft Intune mobile device management policy for a tenant

    .DESCRIPTION
        Caches the Microsoft Intune MDM application policy (0000000a-0000-0000-c000-000000000000),
        including appliesTo, isMdmEnrollmentDuringRegistrationDisabled, the discovery/compliance/terms
        of use URLs and the included groups (displayName).

    .PARAMETER TenantFilter
        The tenant to cache the MDM policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mobile device management policies' -sev Debug

        # Full entity (no $select) so isMdmEnrollmentDuringRegistrationDisabled, appliesTo and the
        # termsOfUseUrl/discoveryUrl/complianceUrl properties are all included, plus included groups
        $MDMPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/mobileDeviceManagementPolicies/0000000a-0000-0000-c000-000000000000?$expand=includedGroups($select=displayName)' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MobileDeviceManagementPolicies' -Data @($MDMPolicy) -AddCount
        $MDMPolicy = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached mobile device management policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mobile device management policies: $($_.Exception.Message)" -sev Error
    }
}
