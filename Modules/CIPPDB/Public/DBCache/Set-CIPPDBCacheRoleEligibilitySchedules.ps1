function Set-CIPPDBCacheRoleEligibilitySchedules {
    <#
    .SYNOPSIS
        Caches role eligibility schedules for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role eligibility schedules for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role eligibility schedules' -sev Debug
        # -AsApp is required: RoleManagement.*.Directory is an APPLICATION permission and only
        # lands in an app-only token. The default delegated path returns "unauthorized".
        # $expand=principal — see the note in Set-CIPPDBCacheRoleAssignmentScheduleInstances;
        # Get-CippDbRoleMembers reads principal.displayName off these records too.
        $Uri = 'https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilitySchedules?$expand=principal'
        New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleEligibilitySchedules' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role eligibility schedules successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role eligibility schedules: $($_.Exception.Message)" -sev Error
    }
}
