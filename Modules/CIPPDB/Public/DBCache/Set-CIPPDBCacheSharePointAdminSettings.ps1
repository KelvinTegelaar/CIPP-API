function Set-CIPPDBCacheSharePointAdminSettings {
    <#
    .SYNOPSIS
        Caches SharePoint tenant admin settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache SharePoint admin settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint admin settings' -sev Debug
        $SharePointSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $TenantFilter -AsApp $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointAdminSettings' -Data @($SharePointSettings) -AddCount
        $SharePointSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint admin settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint admin settings: $($_.Exception.Message)" -sev Error
    }
}
