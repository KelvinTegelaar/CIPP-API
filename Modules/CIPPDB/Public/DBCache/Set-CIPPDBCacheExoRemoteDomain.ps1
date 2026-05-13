function Set-CIPPDBCacheExoRemoteDomain {
    <#
    .SYNOPSIS
        Caches Exchange Online Remote Domains

    .PARAMETER TenantFilter
        The tenant to cache Remote Domain data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Remote Domains' -sev Debug

        $RemoteDomains = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RemoteDomain'
        if ($RemoteDomains) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRemoteDomain' -Data $RemoteDomains
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRemoteDomain' -Data $RemoteDomains -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RemoteDomains.Count) Remote Domains" -sev Debug
        }
        $RemoteDomains = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Remote Domain data: $($_.Exception.Message)" -sev Error
    }
}
