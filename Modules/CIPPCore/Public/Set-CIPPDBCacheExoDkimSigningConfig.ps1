function Set-CIPPDBCacheExoDkimSigningConfig {
    <#
    .SYNOPSIS
        Caches Exchange Online DKIM signing configuration

    .PARAMETER TenantFilter
        The tenant to cache DKIM configuration for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange DKIM signing configuration' -sev Debug

        $DkimConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DkimSigningConfig'

        if ($DkimConfig) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig' -Data $DkimConfig
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoDkimSigningConfig' -Data $DkimConfig -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($DkimConfig.Count) DKIM configurations" -sev Debug
        }
        $DkimConfig = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache DKIM configuration: $($_.Exception.Message)" -sev Error
    }
}
