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

    # A row whose DeltaUrl is blank is as unusable as a missing row: an earlier delta query that
    # ended without a deltaLink persisted an empty value, and handing that to New-GraphDeltaQuery
    # fails parameter binding ("Cannot bind argument to parameter 'DeltaUrl' because it is an
    # empty string") on every scheduled evaluation until the row is rebuilt.
    if ($DeltaQueryEntity -and -not [string]::IsNullOrWhiteSpace($DeltaQueryEntity.DeltaUrl)) {
        return $DeltaQueryEntity.DeltaUrl
    }
    $MissingReason = if ($DeltaQueryEntity) { 'has no delta link' } else { 'is missing' }

    $TaskTable = Get-CIPPTable -TableName 'ScheduledTasks'
    $Task = Get-CIPPAzDataTableEntity @TaskTable -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$PartitionKey'"
    if (!$Task.Trigger) {
        throw "Delta Query for Tenant '$TenantFilter' and PartitionKey '$PartitionKey' $MissingReason, and no scheduled task with a trigger exists to rebuild it from."
    }

    Write-Warning "Delta Query for Tenant '$TenantFilter' and PartitionKey '$PartitionKey' $MissingReason. Rebuilding it from task '$($Task.Name)'."
    $Rebuilt = New-CIPPTaskDeltaQuery -Trigger $Task.Trigger -TenantFilter $TenantFilter -PartitionKey $PartitionKey
    $DeltaUrl = $Rebuilt.'@odata.deltaLink'
    if (!$DeltaUrl) {
        throw "Delta Query for Tenant '$TenantFilter' and PartitionKey '$PartitionKey' $MissingReason and could not be rebuilt."
    }

    Write-LogMessage -API 'Scheduler_UserTasks' -tenant $TenantFilter -message "Rebuilt the missing delta query for task '$($Task.Name)'. Changes from before the rebuild were not captured and will not trigger this task." -sev Warning
    return $DeltaUrl
}
