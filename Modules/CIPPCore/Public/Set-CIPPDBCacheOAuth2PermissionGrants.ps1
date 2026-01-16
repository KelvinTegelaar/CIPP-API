function Set-CIPPDBCacheOAuth2PermissionGrants {
    <#
    .SYNOPSIS
        Caches OAuth2 permission grants (delegated permissions) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache OAuth2 permission grants for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OAuth2 permission grants' -sev Info

        $OAuth2PermissionGrants = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/oauth2PermissionGrants?$top=999' -tenantid $TenantFilter

        if ($OAuth2PermissionGrants) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Data $OAuth2PermissionGrants
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Data $OAuth2PermissionGrants -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($OAuth2PermissionGrants.Count) OAuth2 permission grants" -sev Info
        }
        $OAuth2PermissionGrants = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OAuth2 permission grants: $($_.Exception.Message)" -sev Error
    }
}
