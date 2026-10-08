function ConvertFrom-CIPPCraftRunStatus {
    <#
    .SYNOPSIS
    Shape a Craft run status as a CIPP queue entry

    .DESCRIPTION
    Craft reports runs app-neutrally (QueueStatusBridge.GetRun/GetRuns, and the realtime frames). The queue
    trackers and ListCippQueue use the CippQueue shape the table-backed queue produces, so this maps one to
    the other. frontend/src/utils/craft-run.js does the same for live frames; keep the two in step.

    .PARAMETER Run
    A run status as Craft returns it (ConvertFrom-Json of its camelCase JSON)

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Run
    )

    $Total = [int]$Run.total
    $Done = [int]$Run.completed + [int]$Run.failed
    $Divisor = [Math]::Max($Total, 1)

    [PSCustomObject]@{
        PartitionKey    = 'CippQueue'
        RowKey          = $Run.runName
        Name            = if ($Run.label) { $Run.label } else { $Run.runName }
        Link            = [string]$Run.link
        Reference       = $Run.reference
        TotalTasks      = $Total
        CompletedTasks  = $Done
        RunningTasks    = [int]$Run.running
        FailedTasks     = [int]$Run.failed
        # Midpoints round up, as the frontend's mapper does, so a polled and a pushed entry never differ
        PercentComplete = [math]::Round($Done / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
        PercentFailed   = [math]::Round([int]$Run.failed / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
        PercentRunning  = [math]::Round([int]$Run.running / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
        # Craft names a task by its job name; CIPP's are Function_Tenant and the tracker shows the tenant
        Tasks           = @(foreach ($Task in $Run.tasks) {
                [PSCustomObject]@{ Timestamp = $Task.at; Name = $Task.name -replace '^[^_]*_(?=.)', ''; Status = $Task.status }
            })
        Status          = switch ($Run.status) {
            'CompletedWithErrors' { 'Completed (with errors)' }
            'NotFound' { 'Not found' }
            default { $Run.status }
        }
        Timestamp       = if ($Run.startedUtc) { $Run.startedUtc } else { (Get-Date).ToUniversalTime().ToString('o') }
    }
}
