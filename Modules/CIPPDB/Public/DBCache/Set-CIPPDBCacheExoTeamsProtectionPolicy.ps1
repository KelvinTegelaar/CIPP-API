function Set-CIPPDBCacheExoTeamsProtectionPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online Teams protection policies

    .PARAMETER TenantFilter
        The tenant to cache Teams protection policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Teams protection policies' -sev Debug

        $TeamsProtectionPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TeamsProtectionPolicy'
        if ($TeamsProtectionPolicies) {
            $TeamsProtectionPolicyArray = @($TeamsProtectionPolicies)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTeamsProtectionPolicy' -Data $TeamsProtectionPolicyArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($TeamsProtectionPolicyArray.Count) Teams protection policies" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoTeamsProtectionPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 Teams protection policies (none found)' -sev Debug
        }
        $TeamsProtectionPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams protection policy data: $($_.Exception.Message)" -sev Error
    }
}
