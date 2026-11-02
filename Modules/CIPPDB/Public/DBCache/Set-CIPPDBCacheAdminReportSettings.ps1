function Set-CIPPDBCacheAdminReportSettings {
    <#
    .SYNOPSIS
        Caches admin report settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache admin report settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching admin report settings' -sev Debug
        $ReportSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/reportSettings' -tenantid $TenantFilter -AsApp $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AdminReportSettings' -Data @($ReportSettings) -AddCount
        $ReportSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached admin report settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache admin report settings: $($_.Exception.Message)" -sev Error
    }
}
