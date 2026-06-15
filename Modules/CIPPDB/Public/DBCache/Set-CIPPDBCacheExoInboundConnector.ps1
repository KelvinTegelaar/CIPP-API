function Set-CIPPDBCacheExoInboundConnector {
    <#
    .SYNOPSIS
        Caches Exchange Online inbound connectors

    .PARAMETER TenantFilter
        The tenant to cache inbound connector data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange inbound connectors' -sev Debug

        $InboundConnectors = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-InboundConnector'
        if ($InboundConnectors) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoInboundConnector' -Data $InboundConnectors -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($InboundConnectors.Count) inbound connectors" -sev Debug
        }
        $InboundConnectors = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache inbound connector data: $($_.Exception.Message)" -sev Error
    }
}
