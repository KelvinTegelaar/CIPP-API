function Set-CIPPDBCacheNamePronunciation {
    <#
    .SYNOPSIS
        Caches name pronunciation settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache name pronunciation settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching name pronunciation settings' -sev Debug
        $NamePronunciation = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/people/namePronunciation' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'NamePronunciation' -Data @($NamePronunciation) -AddCount
        $NamePronunciation = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached name pronunciation settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache name pronunciation settings: $($_.Exception.Message)" -sev Error
    }
}
