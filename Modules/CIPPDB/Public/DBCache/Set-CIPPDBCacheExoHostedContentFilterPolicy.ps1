function Set-CIPPDBCacheExoHostedContentFilterPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Hosted Content Filter policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Hosted Content Filter data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Hosted Content Filter policies' -sev Debug
        $HostedContentFilterPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedContentFilterPolicy'
        if ($HostedContentFilterPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterPolicy' -Data $HostedContentFilterPolicies -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($HostedContentFilterPolicies.Count) Hosted Content Filter policies" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Hosted Content Filter policies (none found)' -sev Debug
        }
        $HostedContentFilterPolicies = $null

        # Rules ride along with their policies so a post-write refresh never grades a stale rule.
        Set-CIPPDBCacheExoHostedContentFilterRule -TenantFilter $TenantFilter

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Hosted Content Filter data: $($_.Exception.Message)" -sev Error
    }
}
