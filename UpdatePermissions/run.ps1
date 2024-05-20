# Input bindings are passed in via param block.
param($Timer)

try {
    $Tenants = Get-Tenants -IncludeAll -TriggerRefresh | Where-Object { $_.customerId -ne $env:TenantId -and $_.Excluded -eq $false }
    $Queue = New-CippQueueEntry -Name 'Update Permissions' -TotalTasks ($Tenants | Measure-Object).Count
    $TenantBatch = $Tenants | Select-Object defaultDomainName, customerId, displayName, @{n = 'FunctionName'; exp = { 'UpdatePermissionsQueue' } }, @{n = 'QueueId'; exp = { $Queue.RowKey } }

    if (($Tenants | Measure-Object).Count -gt 0) {
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'UpdatePermissionsOrchestrator'
            Batch            = @($TenantBatch)
        }
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Host "Started permissions orchestration with ID = '$InstanceId'"
    }
} catch {}