function Set-CIPPDBCacheExoRoleAssignmentPolicy {
    <#
    .SYNOPSIS
        Caches Exchange Online role assignment policies

    .PARAMETER TenantFilter
        The tenant to cache role assignment policy data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange role assignment policies' -sev Debug

        $RoleAssignmentPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RoleAssignmentPolicy'
        if ($RoleAssignmentPolicies) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRoleAssignmentPolicy' -Data $RoleAssignmentPolicies -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($RoleAssignmentPolicies.Count) role assignment policies" -sev Debug
        } else {
            # The cmdlet succeeded with nothing returned: write the authoritative empty set so the
            # Count marker records a completed collection and stale rows are cleared.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoRoleAssignmentPolicy' -Data @() -AddCount -ClearOnEmpty
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 role assignment policies (none found)' -sev Debug
        }
        $RoleAssignmentPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role assignment policy data: $($_.Exception.Message)" -sev Error
    }
}
