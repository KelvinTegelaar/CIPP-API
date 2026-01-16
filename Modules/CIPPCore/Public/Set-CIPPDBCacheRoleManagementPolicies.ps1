function Set-CIPPDBCacheRoleManagementPolicies {
    <#
    .SYNOPSIS
        Caches role management policies for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role management policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role management policies' -sev Info
        $RoleManagementPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/roleManagementPolicies' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleManagementPolicies' -Data @($RoleManagementPolicies)
        $RoleManagementPolicies = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role management policies successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role management policies: $($_.Exception.Message)" -sev Error
    }
}
