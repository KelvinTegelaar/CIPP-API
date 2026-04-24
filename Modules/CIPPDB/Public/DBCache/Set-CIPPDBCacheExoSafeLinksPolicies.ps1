function Set-CIPPDBCacheExoSafeLinksPolicies {
    <#
    .SYNOPSIS
        Caches Exchange Online Safe Links policies and rules

    .PARAMETER TenantFilter
        The tenant to cache Safe Links data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange Safe Links policies and rules' -sev Debug

        # Get Safe Links policies
        $SafeLinksPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksPolicy'
        if ($SafeLinksPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies' -Data $SafeLinksPolicies
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksPolicies' -Data $SafeLinksPolicies -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeLinksPolicies.Count) Safe Links policies" -sev Debug
        }
        $SafeLinksPolicies = $null

        # Get Safe Links rules
        $SafeLinksRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksRule'
        if ($SafeLinksRules) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksRules' -Data $SafeLinksRules
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoSafeLinksRules' -Data $SafeLinksRules -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($SafeLinksRules.Count) Safe Links rules" -sev Debug
        }
        $SafeLinksRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Safe Links data: $($_.Exception.Message)" -sev Error
    }
}
