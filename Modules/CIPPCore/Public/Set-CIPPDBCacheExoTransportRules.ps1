function Set-CIPPDBCacheExoTransportRules {
    <#
    .SYNOPSIS
        Caches Exchange Online Transport Rules (Mail Flow Rules)

    .PARAMETER TenantFilter
        The tenant to cache Transport Rules for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Transport Rules' -sev Info

        $TransportRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule'

        if ($TransportRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTransportRules' -Data $TransportRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTransportRules' -Data $TransportRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($TransportRules.Count) Transport Rules" -sev Info
        }
        $TransportRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Transport Rules: $($_.Exception.Message)" -sev Error
    }
}
