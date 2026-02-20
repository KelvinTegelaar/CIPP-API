function Set-CIPPDBCacheLicenseOverview {
    <#
    .SYNOPSIS
        Caches license overview for a tenant

    .PARAMETER TenantFilter
        The tenant to cache license overview for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching license overview' -sev Debug

        $LicenseOverview = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseOverview' -Data @($LicenseOverview)
        $LicenseOverview = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached license overview successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache license overview: $($_.Exception.Message)" -sev Error
    }
}
