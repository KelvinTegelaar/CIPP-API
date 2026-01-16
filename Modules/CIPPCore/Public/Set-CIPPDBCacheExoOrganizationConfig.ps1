function Set-CIPPDBCacheExoOrganizationConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online Organization Configuration

    .PARAMETER TenantFilter
        The tenant to cache organization configuration for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Organization configuration' -sev Debug

        $OrgConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OrganizationConfig'

        if ($OrgConfig) {
            # OrganizationConfig returns a single object, wrap in array for consistency
            $OrgConfigArray = @($OrgConfig)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOrganizationConfig' -Data $OrgConfigArray
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoOrganizationConfig' -Data $OrgConfigArray -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Exchange Organization configuration' -sev Debug
        }
        $OrgConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Organization configuration: $($_.Exception.Message)" -sev Error
    }
}
