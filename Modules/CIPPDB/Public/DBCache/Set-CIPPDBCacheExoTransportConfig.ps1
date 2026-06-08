function Set-CIPPDBCacheExoTransportConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online Transport Configuration

    .PARAMETER TenantFilter
        The tenant to cache transport configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Transport configuration' -sev Debug

        $TransportConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportConfig'

        if ($TransportConfig) {
            # TransportConfig returns a single object, wrap in array for consistency
            $TransportConfigArray = @($TransportConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTransportConfig' -Data $TransportConfigArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange Transport configuration' -sev Debug
        }
        $TransportConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Transport configuration: $($_.Exception.Message)" -sev Error
    }
}
