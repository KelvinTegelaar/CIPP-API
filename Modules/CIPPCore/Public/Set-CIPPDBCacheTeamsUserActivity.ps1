function Set-CIPPDBCacheTeamsUserActivity {
    <#
    .SYNOPSIS
        Caches Teams user activity detail for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Teams user activity for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams user activity' -sev Debug

        $TeamsActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getTeamsUserActivityUserDetail(period='D30')?`$format=application%2fjson" -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsUserActivity' -Data $TeamsActivity
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'TeamsUserActivity' -Data $TeamsActivity -Count
        $TeamsActivity = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Teams user activity successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams user activity: $($_.Exception.Message)" -sev Error
    }
}
