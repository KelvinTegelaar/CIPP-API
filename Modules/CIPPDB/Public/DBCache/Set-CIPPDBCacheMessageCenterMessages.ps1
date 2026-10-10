function Set-CIPPDBCacheMessageCenterMessages {
    <#
    .SYNOPSIS
        Caches Microsoft 365 message center posts for a tenant

    .PARAMETER TenantFilter
        The tenant to cache message center posts for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching message center posts' -sev Debug
        $Messages = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MessageCenterMessages' -Data @($Messages) -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached message center posts successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache message center posts: $($_.Exception.Message)" -sev Error
        throw
    }
}
