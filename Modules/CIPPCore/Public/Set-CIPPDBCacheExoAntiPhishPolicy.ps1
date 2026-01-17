function Set-CIPPDBCacheExoAntiPhishPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Anti-Phish policies (detailed)

    .PARAMETER TenantFilter
        The tenant to cache Anti-Phish policy data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Anti-Phish policies (detailed)' -sev Debug

        $AntiPhishPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishPolicy'
        if ($AntiPhishPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicy' -Data $AntiPhishPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicy' -Data $AntiPhishPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AntiPhishPolicies.Count) Anti-Phish policies (detailed)" -sev Debug
        }
        $AntiPhishPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Anti-Phish policy data: $($_.Exception.Message)" -sev Error
    }
}
