
function Invoke-CIPPStandardsRun {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        [Parameter(Mandatory = $false)]
        $TemplateID,
        [Parameter(Mandatory = $false)]
        $runManually = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Drift
    )
    Write-Information "Starting process for standards - $($tenantFilter). TemplateID: $($TemplateID) RunManually: $($runManually) Force: $($Force.IsPresent) Drift: $($Drift.IsPresent)"

    if ($Drift.IsPresent) {
        Write-Information 'Drift Standards Run'
        $AllTasks = Get-CIPPTenantAlignment | Where-Object -Property standardtype -EQ 'drift' | Select-Object -Property TenantFilter | Sort-Object -Unique -Property TenantFilter

        #For each item in our object, run the queue.
        $Queue = New-CippQueueEntry -Name 'Drift Standards' -TotalTasks ($AllTasks | Measure-Object).Count

        $Batch = foreach ($Task in $AllTasks) {
            [PSCustomObject]@{
                FunctionName = 'CIPPDriftManagement'
                Tenant       = $Task.TenantFilter
            }
        }

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'DriftStandardsOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started orchestration with ID = '$InstanceId' for drift standards run"
        #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
        return
    } else {
        Write-Information 'Classic Standards Run'
        $AllTasks = Get-CIPPStandards

        if ($Force.IsPresent) {
            Write-Information 'Clearing Rerun Cache'
            Test-CIPPRerun -ClearAll -TenantFilter $TenantFilter -Type 'Standard'
        }

        if ($AllTasks.Count -eq 0) {
            Write-Information "No standards found for tenant $($TenantFilter)."
            return
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
            SkipLog          = $true
        }
        if ($TemplateID) {
            $InputObject.QueueFunction.StandardParams['TemplateId'] = $TemplateID
        }
        Write-Information "InputObject: $($InputObject | ConvertTo-Json -Depth 5 -Compress)"
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started orchestration with ID = '$InstanceId'"
        #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    }
}
