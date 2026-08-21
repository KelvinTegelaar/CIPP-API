function Set-CIPPDBCacheExoOutboundConnector {
    <#
    .SYNOPSIS
        Caches Exchange Online outbound connectors

    .PARAMETER TenantFilter
        The tenant to cache outbound connector data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange outbound connectors' -sev Debug

        $OutboundConnectors = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OutboundConnector'
        if ($OutboundConnectors) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOutboundConnector' -Data $OutboundConnectors -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($OutboundConnectors.Count) outbound connectors" -sev Debug
        }
        $OutboundConnectors = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache outbound connector data: $($_.Exception.Message)" -sev Error
    }
}
