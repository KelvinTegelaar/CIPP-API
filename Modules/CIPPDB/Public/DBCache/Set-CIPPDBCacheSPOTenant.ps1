function Set-CIPPDBCacheSPOTenant {
    <#
    .SYNOPSIS
        Caches SharePoint Online tenant configuration

    .DESCRIPTION
        Wraps Get-CIPPSPOTenant (which uses the SPO admin SOAP endpoint via
        New-GraphPostRequest) and writes the result into the CippReportingDB
        under Type 'SPOTenant'. The single configuration object is wrapped in
        an array for consistency with the other ExoOrganizationConfig-style
        single-row caches.

    .PARAMETER TenantFilter
        The tenant to cache SPO tenant configuration for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint Online tenant configuration' -sev Debug

        $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter -SkipCache

        if ($SPOTenant) {
            $SPOTenantArray = @($SPOTenant)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenant' -Data $SPOTenantArray
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenant' -Data $SPOTenantArray -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint Online tenant configuration' -sev Debug
        }
        $SPOTenant = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SPO tenant configuration: $($_.Exception.Message)" -sev Error
    }
}
