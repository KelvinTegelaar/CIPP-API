function Set-CIPPDBCacheActiveUserDetail {
    <#
    .SYNOPSIS
        Caches the Microsoft 365 active-user detail report for a tenant

    .DESCRIPTION
        Stores getOffice365ActiveUserDetail(period='D90') - one row per user carrying per-service
        last-activity dates (Exchange, OneDrive, SharePoint, Teams, Yammer) and the products
        assigned. Rows are keyed by userPrincipalName so they join to the cached Users dataset.

        Note: when the tenant conceals usage-report names, userPrincipalName is anonymized and the
        rows cannot be joined to users. The license optimization report detects this and points to
        the Anonymous Reports Disable standard.

    .PARAMETER TenantFilter
        The tenant to cache active-user detail for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching active user detail' -sev Debug

        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getOffice365ActiveUserDetail(period='D90')?`$format=application%2fjson" -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ActiveUserDetail' -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached active user detail successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache active user detail: $($_.Exception.Message)" -sev Error
    }
}
