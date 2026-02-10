function Set-CIPPDBCacheUsers {
    <#
    .SYNOPSIS
        Caches all users for a tenant

    .PARAMETER TenantFilter
        The tenant to cache users for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching users' -sev Debug

        # Stream users directly from Graph API to batch processor
        # Using $top=500 due to signInActivity limitation
        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=500&$select=signInActivity' -tenantid $TenantFilter |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached users successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache users: $($_.Exception.Message)" -sev Error
    }
}
