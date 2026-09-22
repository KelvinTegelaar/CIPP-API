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

        # Only write when the fetch actually returned the settings object. limitedMode always
        # exists on a tenant that answers this endpoint, so an empty result means the request
        # failed without throwing - writing it anyway would reset the Count marker (and rotate
        # out the previous good row) on a transient Graph error.
        if ($LimitedMode) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotAdminSettings' -Data @($LimitedMode) -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot admin settings successfully' -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot admin settings fetch returned no data - leaving the existing cache untouched' -sev Warning
        }
        $LimitedMode = $null

    } catch {
        # A transient Graph error must not touch the cache: the last good settings row stays in
        # place and the next successful run replaces it.
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot admin settings: $($_.Exception.Message)" -sev Debug
    }
}
