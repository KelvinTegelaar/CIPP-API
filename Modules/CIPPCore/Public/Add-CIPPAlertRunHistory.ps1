function Add-CIPPAlertRunHistory {
    <#
    .SYNOPSIS
        Records one scripted alert run for one tenant in the AlertRunHistory table.
    .DESCRIPTION
        Rows are partitioned by UTC day (yyyyMMdd) with a newest-first RowKey, so a list of recent runs reads
        a few day partitions instead of scanning the table, and cleanup drops whole days by partition range.
        With -RecordCompletion it also stamps the 'LastRun' marker that the scheduler's minimum-interval check
        reads for this task and tenant. The marker holds the run's scheduled slot, not when a worker picked it up,
        so a late pickup does not shift later runs. A failed write is logged and never fails the alert run.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$Tenant,
        [string]$TenantId,
        [Parameter(Mandatory = $true)][ValidateSet('Completed', 'Skipped', 'Failed', 'Not reported')][string]$Outcome,
        [string]$Summary,
        [hashtable]$Counts,
        [datetime]$StartedUtc = [datetime]::UtcNow,
        # The slot the run was scheduled for (the task's ScheduledTime); defaults to StartedUtc.
        [Nullable[datetime]]$ScheduledUtc,
        [int64]$DurationMs = 0,
        [switch]$RecordCompletion
    )

    try {
        $Table = Get-CIPPTable -tablename 'AlertRunHistory'
        $TenantKey = if ($TenantId) { $TenantId } else { $Tenant }
        $Slot = $ScheduledUtc ?? $StartedUtc
        $Entity = @{
            PartitionKey = $StartedUtc.ToString('yyyyMMdd')
            RowKey       = '{0:D19}_{1}_{2}' -f ([datetime]::MaxValue.Ticks - $StartedUtc.Ticks), $Task.RowKey, $TenantKey
            TaskId       = [string]$Task.RowKey
            TaskName     = [string]$Task.Name
            Alert        = [string]$Task.Command -replace '^Get-CIPPAlert', ''
            Tenant       = $Tenant
            TenantId     = [string]$TenantId
            Outcome      = $Outcome
            Summary      = [string]$Summary
            StartedUtc   = $StartedUtc.ToString('o')
            ScheduledUtc = $Slot.ToString('o')
            DurationMs   = $DurationMs
        }
        foreach ($Key in 'New', 'Reopened', 'Continuing', 'Resolved', 'Snoozed') {
            $Entity[$Key] = [int]($Counts.$Key ?? 0)
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        if ($RecordCompletion) {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'LastRun'
                RowKey       = '{0}_{1}' -f $Task.RowKey, $TenantKey
                LastSlotUtc  = $Slot.ToString('o')
            } -Force | Out-Null
        }
    } catch {
        Write-Information "Could not record the alert run for $($Task.Name) / $Tenant : $($_.Exception.Message)"
    }
}
