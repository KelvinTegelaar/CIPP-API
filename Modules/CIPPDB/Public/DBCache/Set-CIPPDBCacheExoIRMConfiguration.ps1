function Set-CIPPDBCacheExoIRMConfiguration {
    <#
    .SYNOPSIS
        Caches the Exchange Online IRM configuration

    .PARAMETER TenantFilter
        The tenant to cache IRM configuration data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange IRM configuration' -sev Debug

        $IRMConfiguration = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-IRMConfiguration'
        if ($IRMConfiguration) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoIRMConfiguration' -Data @($IRMConfiguration) -AddCount
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoIRMConfiguration' -Data @() -AddCount -ClearOnEmpty
        }
        $IRMConfiguration = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache IRM configuration data: $($_.Exception.Message)" -sev Error
    }
}
