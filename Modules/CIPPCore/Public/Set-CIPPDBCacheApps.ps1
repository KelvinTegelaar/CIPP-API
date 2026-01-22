function Set-CIPPDBCacheApps {
    <#
    .SYNOPSIS
        Caches all application registrations for a tenant

    .PARAMETER TenantFilter
        The tenant to cache applications for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching applications' -sev Debug

        $Apps = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/applications?$top=999&expand=owners' -tenantid $TenantFilter
        if (!$Apps) { $Apps = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Apps' -Data $Apps
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Apps' -Data $Apps -Count
        $Apps = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached applications successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache applications: $($_.Exception.Message)" -sev Error
    }
}
