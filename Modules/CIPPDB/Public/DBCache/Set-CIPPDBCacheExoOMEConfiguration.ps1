function Set-CIPPDBCacheExoOMEConfiguration {
    <#
    .SYNOPSIS
        Caches Exchange Online Message Encryption (OME) configurations

    .PARAMETER TenantFilter
        The tenant to cache OME configuration data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange OME configurations' -sev Debug

        $OMEConfigurations = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OMEConfiguration'
        if ($OMEConfigurations) {
            $OMEConfigurationArray = @($OMEConfigurations)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOMEConfiguration' -Data $OMEConfigurationArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($OMEConfigurationArray.Count) OME configurations" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOMEConfiguration' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 OME configurations (none found)' -sev Debug
        }
        $OMEConfigurations = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OME configuration data: $($_.Exception.Message)" -sev Error
    }
}
