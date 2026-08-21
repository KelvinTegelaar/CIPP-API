function Set-CIPPDBCacheSecurityDefaults {
    <#
    .SYNOPSIS
        Caches the identity security defaults enforcement policy for a tenant

    .DESCRIPTION
        Set-CIPPDBCacheConditionalAccessPolicies also writes this Type, but that collector
        returns early for tenants without Entra Premium - exactly the tenants Security
        Defaults applies to. This ungated collector keeps the cache populated for them, and
        gives the Baselines engine a Set-CIPPDBCache<cacheType> to call on a read miss.
        Both writers produce the same row key (Type + policy id), so the write is an upsert.

    .PARAMETER TenantFilter
        The tenant to cache the security defaults policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Security Defaults policy' -sev Debug

        $SecurityDefaults = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter -AsApp $true
        if ($SecurityDefaults) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecurityDefaults' -Data @($SecurityDefaults)
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached Security Defaults policy (isEnabled=$($SecurityDefaults.isEnabled))" -sev Debug
        }
        $SecurityDefaults = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Security Defaults: $($_.Exception.Message)" -sev Error
    }
}
