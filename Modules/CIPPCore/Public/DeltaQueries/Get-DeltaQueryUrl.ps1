function Get-DeltaQueryUrl {
    <#
    .SYNOPSIS
        Retrieves the URL for Delta Queries
    .DESCRIPTION
        This helper function constructs the URL for Delta Query requests based on the resource and parameters.
        If the DeltaQueries row is missing it is rebuilt from the owning scheduled task's trigger.
    .PARAMETER TenantFilter
        The tenant to filter the query on.
    .PARAMETER PartitionKey
        The partition key for the delta query. This is the RowKey of the scheduled task that owns it.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $PartitionKey
    )

    $Table = Get-CIPPTable -TableName 'DeltaQueries'
    $DeltaQueryEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$PartitionKey' and RowKey eq '$TenantFilter'"

    if ($DeltaQueryEntity) {
        return $DeltaQueryEntity.DeltaUrl
    }

    $TaskTable = Get-CIPPTable -TableName 'ScheduledTasks'
    $Task = Get-CIPPAzDataTableEntity @TaskTable -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$PartitionKey'"
    if (!$Task.Trigger) {
        throw "Delta Query not found for Tenant '$TenantFilter' and PartitionKey '$PartitionKey', and no scheduled task with a trigger exists to rebuild it from."
    }

    Write-Warning "Delta Query missing for Tenant '$TenantFilter' and PartitionKey '$PartitionKey'. Rebuilding it from task '$($Task.Name)'."
    $Rebuilt = New-CIPPTaskDeltaQuery -Trigger $Task.Trigger -TenantFilter $TenantFilter -PartitionKey $PartitionKey
    $DeltaUrl = $Rebuilt.'@odata.deltaLink'
    if (!$DeltaUrl) {
        throw "Delta Query not found for Tenant '$TenantFilter' and PartitionKey '$PartitionKey' and could not be rebuilt."
    }

    Write-LogMessage -API 'Scheduler_UserTasks' -tenant $TenantFilter -message "Rebuilt the missing delta query for task '$($Task.Name)'. Changes from before the rebuild were not captured and will not trigger this task." -sev Warning
    return $DeltaUrl
}
