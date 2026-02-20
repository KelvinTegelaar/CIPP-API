function Set-CIPPDBCacheIntuneAppProtectionPolicies {
    <#
    .SYNOPSIS
        Caches Intune App Protection Policies

    .PARAMETER TenantFilter
        The tenant to cache app protection policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune App Protection Policies' -sev Debug

        # iOS Managed App Protection Policies
        $IosPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?$expand=assignments' -tenantid $TenantFilter
        if ($IosPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneIosAppProtectionPolicies' -Data $IosPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneIosAppProtectionPolicies' -Data $IosPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($IosPolicies.Count) iOS app protection policies" -sev Debug
        }
        $IosPolicies = $null

        # Android Managed App Protection Policies
        $AndroidPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?$expand=assignments' -tenantid $TenantFilter
        if ($AndroidPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAndroidAppProtectionPolicies' -Data $AndroidPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAndroidAppProtectionPolicies' -Data $AndroidPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AndroidPolicies.Count) Android app protection policies" -sev Debug
        }
        $AndroidPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache App Protection Policies: $($_.Exception.Message)" -sev Error
    }
}
