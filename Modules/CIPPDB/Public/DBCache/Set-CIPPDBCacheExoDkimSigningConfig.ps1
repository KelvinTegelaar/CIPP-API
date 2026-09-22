function Set-CIPPDBCacheExoDkimSigningConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online DKIM signing configuration

    .PARAMETER TenantFilter
        The tenant to cache DKIM configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange DKIM signing configuration' -sev Debug

        $DkimConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DkimSigningConfig'

        if ($DkimConfig) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig' -Data $DkimConfig -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($DkimConfig.Count) DKIM configurations" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 DKIM configurations (none found)' -sev Debug
        }
        $DkimConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache DKIM configuration: $($_.Exception.Message)" -sev Error
    }
}
