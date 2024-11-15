
function Invoke-CIPPStandardsRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [switch]$Force
    )
    Write-Information "Starting process for standards - $($tenantFilter)"

    $AllTasks = Get-CIPPStandards -TenantFilter $TenantFilter

    if ($Force.IsPresent) {
        Write-Information 'Clearing Rerun Cache'
        foreach ($Task in $AllTasks) {
            $null = Test-CIPPRerun -Type Standard -Tenant $Task.Tenant -API $Task.Standard -Clear
        }
    }
    $TaskCount = ($AllTasks | Measure-Object).Count

    if ($TaskCount -eq 0) {
        Write-Information "No tasks found for tenant filter '$TenantFilter'"
        return
    }

    Write-Information "Found $TaskCount tasks for tenant filter '$TenantFilter'"
    #For each item in our object, run the queue.
    $Queue = New-CippQueueEntry -Name "Applying Standards ($TenantFilter)" -TotalTasks $TaskCount

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

    Write-Information 'Starting standards orchestrator'
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Information "Started orchestration with ID = '$InstanceId'"
    #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    return $InstanceId
}
