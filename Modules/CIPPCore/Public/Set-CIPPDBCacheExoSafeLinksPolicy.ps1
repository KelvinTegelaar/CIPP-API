function Set-CIPPDBCacheExoSafeLinksPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Links policies (detailed)

    .PARAMETER TenantFilter
        The tenant to cache Safe Links policy data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Links policies (detailed)' -sev Debug

        $SafeLinksPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksPolicy'
        if ($SafeLinksPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicy' -Data $SafeLinksPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicy' -Data $SafeLinksPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeLinksPolicies.Count) Safe Links policies (detailed)" -sev Debug
        }
        $SafeLinksPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Links policy data: $($_.Exception.Message)" -sev Error
    }
}
