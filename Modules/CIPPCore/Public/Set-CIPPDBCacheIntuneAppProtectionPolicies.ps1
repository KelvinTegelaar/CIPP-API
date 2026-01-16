function Set-CIPPDBCacheIntuneAppProtectionPolicies {
    <#
    .SYNOPSIS
        Caches Intune App Protection Policies

    .PARAMETER TenantFilter
        The tenant to cache app protection policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune App Protection Policies' -sev Info

        # iOS Managed App Protection Policies
        $IosPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections?$expand=assignments' -tenantid $TenantFilter
        if ($IosPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneIosAppProtectionPolicies' -Data $IosPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneIosAppProtectionPolicies' -Data $IosPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($IosPolicies.Count) iOS app protection policies" -sev Info
        }
        $IosPolicies = $null

        # Android Managed App Protection Policies
        $AndroidPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections?$expand=assignments' -tenantid $TenantFilter
        if ($AndroidPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAndroidAppProtectionPolicies' -Data $AndroidPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneAndroidAppProtectionPolicies' -Data $AndroidPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AndroidPolicies.Count) Android app protection policies" -sev Info
        }
        $AndroidPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache App Protection Policies: $($_.Exception.Message)" -sev Error
    }
}
