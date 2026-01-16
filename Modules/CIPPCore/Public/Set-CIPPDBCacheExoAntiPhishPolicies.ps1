function Set-CIPPDBCacheExoAntiPhishPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Anti-Phishing policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Anti-Phishing data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Anti-Phishing policies and rules' -sev Debug

        # Get Anti-Phishing policies
        $AntiPhishPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishPolicy'
        if ($AntiPhishPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies' -Data $AntiPhishPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies' -Data $AntiPhishPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AntiPhishPolicies.Count) Anti-Phishing policies" -sev Debug
        }
        $AntiPhishPolicies = $null

        # Get Anti-Phishing rules
        $AntiPhishRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishRule'
        if ($AntiPhishRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -Data $AntiPhishRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -Data $AntiPhishRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AntiPhishRules.Count) Anti-Phishing rules" -sev Debug
        }
        $AntiPhishRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Anti-Phishing data: $($_.Exception.Message)" -sev Error
    }
}
