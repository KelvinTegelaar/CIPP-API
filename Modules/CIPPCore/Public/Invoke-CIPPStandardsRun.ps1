
function Invoke-CIPPStandardsRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        [Parameter(Mandatory = $false)]
        $TemplateID,
        [Parameter(Mandatory = $false)]
        $runManually = $false

    )
    Write-Host "Starting process for standards - $($tenantFilter)"

    $AllTasks = Get-CIPPStandards

    if ($Force.IsPresent) {
        Write-Host 'Clearing Rerun Cache'
        foreach ($Task in $AllTasks) {
            Write-Host "Clearing $($Task.Standard)_$($TemplateID)"
            $null = Test-CIPPRerun -Type Standard -Tenant $Task.Tenant -API "$($Task.Standard)_$($TemplateID)" -Clear
        }
    }

    #For each item in our object, run the queue.
    $Queue = New-CippQueueEntry -Name "Applying Standards ($TenantFilter)" -TotalTasks ($AllTasks | Measure-Object).Count

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'StandardsOrchestrator'
        QueueFunction    = @{
            FunctionName   = 'GetStandards'
            QueueId        = $Queue.RowKey
            StandardParams = @{
                TenantFilter = $TenantFilter
                runManually  = $runManually
            }
        }
    }
    if ($TemplateID) {
        $InputObject.QueueFunction.StandardParams['TemplateId'] = $TemplateID
    }
    Write-Host "InputObject: $($InputObject | ConvertTo-Json -Depth 5 -Compress)"
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Host "Started orchestration with ID = '$InstanceId'"
    #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
}
