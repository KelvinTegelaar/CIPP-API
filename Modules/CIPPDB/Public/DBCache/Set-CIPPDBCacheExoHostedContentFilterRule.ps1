function Set-CIPPDBCacheExoHostedContentFilterRule {
    <#
    .SYNOPSIS
        Caches Exchange Online hosted content filter (anti-spam) rules

    .PARAMETER TenantFilter
        The tenant to cache hosted content filter rule data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange hosted content filter rules' -sev Debug

        $HostedContentFilterRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedContentFilterRule'
        if ($HostedContentFilterRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterRule' -Data $HostedContentFilterRules -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($HostedContentFilterRules.Count) hosted content filter rules" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoHostedContentFilterRule' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 hosted content filter rules (none found)' -sev Debug
        }
        $HostedContentFilterRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache hosted content filter rule data: $($_.Exception.Message)" -sev Error
    }
}
