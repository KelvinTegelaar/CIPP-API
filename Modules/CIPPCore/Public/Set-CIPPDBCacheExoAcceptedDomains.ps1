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
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains' -Data $AcceptedDomains
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains' -Data $AcceptedDomains -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AcceptedDomains.Count) Accepted Domains" -sev Debug
        }
        $AcceptedDomains = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Accepted Domains: $($_.Exception.Message)" -sev Error
    }
}
