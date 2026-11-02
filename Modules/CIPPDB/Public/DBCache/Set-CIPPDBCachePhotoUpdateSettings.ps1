function Set-CIPPDBCachePhotoUpdateSettings {
    <#
    .SYNOPSIS
        Caches profile photo update settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache photo update settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching photo update settings' -sev Debug
        # The old ProfilePhotos standard reads this endpoint with the default delegated token (AsApp is only used for writes)
        $PhotoUpdateSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PhotoUpdateSettings' -Data @($PhotoUpdateSettings) -AddCount
        $PhotoUpdateSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached photo update settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache photo update settings: $($_.Exception.Message)" -sev Error
    }
}
