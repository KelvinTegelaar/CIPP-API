function Set-CIPPDBCacheRolesAndAssignments {
    <#
    .SYNOPSIS
        Refreshes every reporting DB cache that feeds the Roles & Assignments page

    .DESCRIPTION
        The cached Roles & Assignments view is compiled at read time from existing cache types, so
        this collector writes no rows of its own — it runs the source collectors sequentially so a
        single on-demand sync refreshes all of them.

    .PARAMETER TenantFilter
        The tenant to refresh the source caches for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $SourceTypes = @(
        'Roles'
        'RoleDefinitions'
        'RoleAssignments'
        'AdministrativeUnits'
        'RoleAssignmentScheduleInstances'
        'RoleEligibilitySchedules'
        'RoleManagementPolicies'
    )

    foreach ($SourceType in $SourceTypes) {
        $FunctionName = "Set-CIPPDBCache$SourceType"
        try {
            $Params = @{ TenantFilter = $TenantFilter }
            if ($QueueId) { $Params.QueueId = $QueueId }
            & $FunctionName @Params
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Roles & Assignments sync: failed to refresh $SourceType : $($_.Exception.Message)" -sev Warning
        }
    }
}
