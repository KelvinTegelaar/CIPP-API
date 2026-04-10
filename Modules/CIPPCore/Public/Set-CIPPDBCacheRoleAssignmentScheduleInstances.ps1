function Set-CIPPDBCacheRoleAssignmentScheduleInstances {
    <#
    .SYNOPSIS
        Caches role assignment schedule instances for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role assignment schedule instances for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role assignment schedule instances' -sev Debug
        $RoleAssignmentScheduleInstances = New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances' -Data @($RoleAssignmentScheduleInstances)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleAssignmentScheduleInstances' -Data @($RoleAssignmentScheduleInstances) -Count
        $RoleAssignmentScheduleInstances = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role assignment schedule instances successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role assignment schedule instances: $($_.Exception.Message)" -sev Error
    }
}
