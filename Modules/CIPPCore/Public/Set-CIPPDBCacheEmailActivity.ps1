function Set-CIPPDBCacheEmailActivity {
    <#
    .SYNOPSIS
        Caches email activity user detail for a tenant

    .PARAMETER TenantFilter
        The tenant to cache email activity for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching email activity' -sev Debug

        $EmailActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getEmailActivityUserDetail(period='D30')?`$format=application%2fjson" -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'EmailActivity' -Data $EmailActivity
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'EmailActivity' -Data $EmailActivity -Count
        $EmailActivity = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached email activity successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache email activity: $($_.Exception.Message)" -sev Error
    }
}
