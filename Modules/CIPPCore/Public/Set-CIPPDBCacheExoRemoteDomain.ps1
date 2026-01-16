function Set-CIPPDBCacheExoRemoteDomain {
    <#
    .SYNOPSIS
        Caches Exchange Online Remote Domains

    .PARAMETER TenantFilter
        The tenant to cache Remote Domain data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Remote Domains' -sev Info

        $RemoteDomains = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RemoteDomain'
        if ($RemoteDomains) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRemoteDomain' -Data $RemoteDomains
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRemoteDomain' -Data $RemoteDomains -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RemoteDomains.Count) Remote Domains" -sev Info
        }
        $RemoteDomains = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Remote Domain data: $($_.Exception.Message)" -sev Error
    }
}
