function Set-CIPPDBCacheExoOrganizationConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online Organization Configuration

    .PARAMETER TenantFilter
        The tenant to cache organization configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Organization configuration' -sev Debug

        $OrgConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OrganizationConfig'

        if ($OrgConfig) {
            # OrganizationConfig returns a single object, wrap in array for consistency
            $OrgConfigArray = @($OrgConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOrganizationConfig' -Data $OrgConfigArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange Organization configuration' -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOrganizationConfig' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Organization configurations (none found)' -sev Debug
        }
        $OrgConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Organization configuration: $($_.Exception.Message)" -sev Error
    }
}
