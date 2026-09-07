function Set-CIPPDBCacheExoHostedConnectionFilterPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online hosted connection filter policies

    .PARAMETER TenantFilter
        The tenant to cache hosted connection filter policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange hosted connection filter policies' -sev Debug

        $ConnectionFilterPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedConnectionFilterPolicy'
        if ($ConnectionFilterPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedConnectionFilterPolicy' -Data $ConnectionFilterPolicies -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ConnectionFilterPolicies.Count) hosted connection filter policies" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedConnectionFilterPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 hosted connection filter policies (none found)' -sev Debug
        }
        $ConnectionFilterPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache hosted connection filter policy data: $($_.Exception.Message)" -sev Error
    }
}
