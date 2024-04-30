
function Invoke-CIPPStandardsRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants'
    )
    Write-Host "Starting process for standards - $($tenantFilter)"

    $AllTasks = Get-CIPPStandards -TenantFilter $TenantFilter

    #For each item in our object, run the queue.
    $Queue = New-CippQueueEntry -Name "Applying Standards ($TenantFilter)" -TotalTasks ($AllTasks | Measure-Object).Count
    $Batch = foreach ($task in $AllTasks) {
        [PSCustomObject]@{
            Tenant       = $task.Tenant
            Standard     = $task.Standard
            Settings     = $task.Settings
            QueueId      = $Queue.RowKey
            QueueName    = '{0} - {1}' -f $task.Standard, $Task.Tenant
            FunctionName = 'CIPPStandard'
        }
    }

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'Standards'
        Batch            = @($Batch)
    }

    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Host "Started orchestration with ID = '$InstanceId'"
    #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
}