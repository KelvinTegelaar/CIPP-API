function Set-CIPPDBCacheM365AppUserDetail {
    <#
    .SYNOPSIS
        Caches the Microsoft 365 Apps usage detail report for a tenant

    .DESCRIPTION
        Stores getM365AppUserDetail(period='D180') - one row per user with, per platform (Windows,
        Mac, mobile, web), whether each Office app (Outlook, Word, Excel, PowerPoint, OneNote,
        Teams) was used in the period. Rows are keyed by userPrincipalName so they join to the
        cached Users dataset. D180 is the longest Graph window so license optimization can filter
        to any inactive threshold.

        The license recommendation report uses the Windows/Mac columns to tell whether a user
        actually runs the installed desktop apps their plan pays for.

        Note: when the tenant conceals usage-report names, userPrincipalName is anonymized and the
        rows cannot be joined to users. The report detects this and points to the Anonymous
        Reports Disable standard.

    .PARAMETER TenantFilter
        The tenant to cache app usage detail for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Microsoft 365 app usage detail' -sev Debug

        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getM365AppUserDetail(period='D180')?`$format=application%2fjson" -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'M365AppUserDetail' -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Microsoft 365 app usage detail successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Microsoft 365 app usage detail: $($_.Exception.Message)" -sev Error
    }
}
