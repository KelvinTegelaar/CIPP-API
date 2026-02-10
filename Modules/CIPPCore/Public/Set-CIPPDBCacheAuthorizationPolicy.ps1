function Set-CIPPDBCacheAuthorizationPolicy {
    <#
    .SYNOPSIS
        Caches authorization policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache authorization policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching authorization policy' -sev Debug
        $AuthPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AuthorizationPolicy' -Data @($AuthPolicy)
        $AuthPolicy = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached authorization policy successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache authorization policy: $($_.Exception.Message)" -sev Error
    }
}
