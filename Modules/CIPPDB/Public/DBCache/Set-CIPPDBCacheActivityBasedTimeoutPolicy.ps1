function Set-CIPPDBCacheActivityBasedTimeoutPolicy {
    <#
    .SYNOPSIS
        Caches activity based timeout policies for a tenant

    .PARAMETER TenantFilter
        The tenant to cache activity based timeout policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching activity based timeout policies' -sev Debug
        $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ActivityBasedTimeoutPolicy' -Data @($Policies | Where-Object { $_.id }) -AddCount -ClearOnEmpty
        $Policies = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached activity based timeout policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache activity based timeout policies: $($_.Exception.Message)" -sev Error
    }
}
