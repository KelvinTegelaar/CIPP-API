function Set-CIPPDBCacheExoTransportRules {
    <#
    .SYNOPSIS
        Caches Exchange Online Transport Rules (Mail Flow Rules)

    .PARAMETER TenantFilter
        The tenant to cache Transport Rules for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Transport Rules' -sev Debug

        $TransportRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule'

        if ($TransportRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTransportRules' -Data $TransportRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTransportRules' -Data $TransportRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($TransportRules.Count) Transport Rules" -sev Debug
        }
        $TransportRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Transport Rules: $($_.Exception.Message)" -sev Error
    }
}
