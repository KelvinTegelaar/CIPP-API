function Set-CIPPDBCacheExoAcceptedDomains {
    <#
    .SYNOPSIS
        Caches Exchange Online Accepted Domains

    .PARAMETER TenantFilter
        The tenant to cache accepted domains for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Accepted Domains' -sev Debug

        $AcceptedDomains = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AcceptedDomain'

        if ($AcceptedDomains) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains' -Data $AcceptedDomains -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AcceptedDomains.Count) Accepted Domains" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Accepted Domains (none found)' -sev Debug
        }
        $AcceptedDomains = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Accepted Domains: $($_.Exception.Message)" -sev Error
    }
}
