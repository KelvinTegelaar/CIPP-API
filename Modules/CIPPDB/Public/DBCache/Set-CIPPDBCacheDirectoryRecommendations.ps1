function Set-CIPPDBCacheDirectoryRecommendations {
    <#
    .SYNOPSIS
        Caches directory recommendations for a tenant

    .PARAMETER TenantFilter
        The tenant to cache recommendations for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory recommendations' -sev Debug

        $Recommendations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/recommendations?$top=999' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DirectoryRecommendations' -Data $Recommendations
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DirectoryRecommendations' -Data $Recommendations -Count
        $Recommendations = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory recommendations successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory recommendations: $($_.Exception.Message)" -sev Error
    }
}
