function Set-CIPPDBCacheDirectoryRecommendations {
    <#
    .SYNOPSIS
        Caches directory recommendations for a tenant

    .PARAMETER TenantFilter
        The tenant to cache recommendations for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory recommendations' -sev Info

        $Recommendations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/recommendations?$top=999' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DirectoryRecommendations' -Data $Recommendations
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DirectoryRecommendations' -Data $Recommendations -Count
        $Recommendations = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory recommendations successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory recommendations: $($_.Exception.Message)" -sev Error
    }
}
