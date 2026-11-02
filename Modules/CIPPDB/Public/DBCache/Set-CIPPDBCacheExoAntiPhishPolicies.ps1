function Set-CIPPDBCacheExoAntiPhishPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Anti-Phishing policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Anti-Phishing data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Anti-Phishing policies and rules' -sev Debug

        # Get Anti-Phishing policies
        $AntiPhishPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishPolicy'
        if ($AntiPhishPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies' -Data $AntiPhishPolicies -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AntiPhishPolicies.Count) Anti-Phishing policies" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishPolicies' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Anti-Phishing policies (none found)' -sev Debug
        }
        $AntiPhishPolicies = $null

        # Get Anti-Phishing rules
        $AntiPhishRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AntiPhishRule'
        if ($AntiPhishRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -Data $AntiPhishRules -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AntiPhishRules.Count) Anti-Phishing rules" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAntiPhishRules' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Anti-Phishing rules (none found)' -sev Debug
        }
        $AntiPhishRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Anti-Phishing data: $($_.Exception.Message)" -sev Error
    }
}
