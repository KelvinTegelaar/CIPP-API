
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

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'StandardsOrchestrator'
        QueueFunction    = @{
            FunctionName   = 'GetStandards'
            QueueId        = $Queue.RowKey
            StandardParams = @{
                TenantFilter = $TenantFilter
            }
        }
    }

    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Host "Started orchestration with ID = '$InstanceId'"
    #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
}