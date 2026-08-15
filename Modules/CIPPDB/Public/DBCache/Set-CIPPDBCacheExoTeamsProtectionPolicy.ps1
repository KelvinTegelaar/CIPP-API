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
        }
        $TeamsProtectionPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams protection policy data: $($_.Exception.Message)" -sev Error
    }
}
