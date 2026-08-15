function Set-CIPPDBCacheCopilotAdminSettings {
    <#
    .SYNOPSIS
        Caches Copilot admin limited mode settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Copilot admin settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot admin settings' -sev Debug

        # The Copilot admin settings API currently requires delegated auth (no -AsApp)
        $LimitedMode = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/copilot/admin/settings/limitedMode' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotAdminSettings' -Data @($LimitedMode) -AddCount
        $LimitedMode = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot admin settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot admin settings: $($_.Exception.Message)" -sev Error
    }
}
