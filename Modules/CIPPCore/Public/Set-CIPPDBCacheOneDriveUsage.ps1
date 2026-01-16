function Set-CIPPDBCacheOneDriveUsage {
    <#
    .SYNOPSIS
        Caches OneDrive usage details for a tenant

    .PARAMETER TenantFilter
        The tenant to cache OneDrive usage for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OneDrive usage' -sev Debug

        $OneDriveUsage = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOneDriveUsageAccountDetail(period='D7')?`$format=application%2fjson" -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveUsage' -Data $OneDriveUsage
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveUsage' -Data $OneDriveUsage -Count
        $OneDriveUsage = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached OneDrive usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OneDrive usage: $($_.Exception.Message)" -sev Error
    }
}
