function Set-CIPPDBCacheExoHostedContentFilterPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Hosted Content Filter policies

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
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterPolicy' -Data $HostedContentFilterPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterPolicy' -Data $HostedContentFilterPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($HostedContentFilterPolicies.Count) Hosted Content Filter policies" -sev Debug
        }
        $HostedContentFilterPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Hosted Content Filter data: $($_.Exception.Message)" -sev Error
    }
}
