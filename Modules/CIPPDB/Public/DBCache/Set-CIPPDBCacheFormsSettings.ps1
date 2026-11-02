function Set-CIPPDBCacheFormsSettings {
    <#
    .SYNOPSIS
        Caches Microsoft Forms settings for a tenant

    .DESCRIPTION
        Forms settings are normally cached by Set-CIPPDBCacheSettings as part of its bulk request.
        This collector re-runs the same fetch and writes the same Type so the engine's on-miss
        Set-CIPPDBCache<Type> lookup resolves for 'FormsSettings'.

    .PARAMETER TenantFilter
        The tenant to cache Forms settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Forms settings' -sev Debug

        $FormsSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/forms/settings' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'FormsSettings' -Data @($FormsSettings) -AddCount
        $FormsSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Forms settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Forms settings: $($_.Exception.Message)" -sev Error
    }
}
