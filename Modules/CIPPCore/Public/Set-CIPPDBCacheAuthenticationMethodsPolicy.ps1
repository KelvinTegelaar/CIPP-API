function Set-CIPPDBCacheAuthenticationMethodsPolicy {
    <#
    .SYNOPSIS
        Caches authentication methods policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache authentication methods policy for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching authentication methods policy' -sev Debug
        $AuthMethodsPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthenticationMethodsPolicy' -Data @($AuthMethodsPolicy)
        $AuthMethodsPolicy = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached authentication methods policy successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authentication methods policy: $($_.Exception.Message)" -sev Error
    }
}
