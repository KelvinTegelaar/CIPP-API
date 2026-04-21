function Set-CIPPDBCacheExoHostedOutboundSpamFilterPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Hosted Outbound Spam Filter policies

    .PARAMETER TenantFilter
        The tenant to cache Hosted Outbound Spam Filter data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Hosted Outbound Spam Filter policies' -sev Debug

        $HostedOutboundSpamFilterPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedOutboundSpamFilterPolicy'
        if ($HostedOutboundSpamFilterPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedOutboundSpamFilterPolicy' -Data $HostedOutboundSpamFilterPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedOutboundSpamFilterPolicy' -Data $HostedOutboundSpamFilterPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($HostedOutboundSpamFilterPolicies.Count) Hosted Outbound Spam Filter policies" -sev Debug
        }
        $HostedOutboundSpamFilterPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Hosted Outbound Spam Filter data: $($_.Exception.Message)" -sev Error
    }
}
