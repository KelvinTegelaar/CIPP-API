function Set-CIPPDBCacheAdminConsentRequestPolicy {
    <#
    .SYNOPSIS
        Caches admin consent request policy and settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache consent policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching admin consent request policy' -sev Debug
        $ConsentPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AdminConsentRequestPolicy' -Data @($ConsentPolicy)
        $ConsentPolicy = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached admin consent request policy successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache admin consent request policy: $($_.Exception.Message)" -sev Error
    }
}
