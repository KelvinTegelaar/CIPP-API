param($Timer)

try {
    $webhookTable = Get-CIPPTable -tablename webhookTable
    $Webhooks = Get-CIPPAzDataTableEntity @webhookTable -Filter "Version eq '3'" | Where-Object { $_.Resource -match '^Audit' }
    if (($Webhooks | Measure-Object).Count -eq 0) {
        Write-Host 'No webhook subscriptions found. Exiting.'
        return
    }

    <#try {
        $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq 'AuditLogCollection' -and $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' -and $_.Timestamp.DateTime.ToLocalTime() -lt (Get-Date).AddMinutes(-10) }
        if ($RunningQueue) {
            Write-Host 'Audit log collection already running'
            return
        }
    } catch {}#>

    $StartTime = (Get-Date).AddMinutes(-30)
    $EndTime = Get-Date

    $Queue = New-CippQueueEntry -Name 'Audit Log Collection' -Reference 'AuditLogCollection' -TotalTasks ($Webhooks | Sort-Object -Property PartitionKey -Unique | Measure-Object).Count
    $Batch = $Webhooks | Sort-Object -Property PartitionKey -Unique | Select-Object @{Name = 'TenantFilter'; Expression = { $_.PartitionKey } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogTenant' } }, @{Name = 'StartTime'; Expression = { $StartTime } }, @{Name = 'EndTime'; Expression = { $EndTime } }
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'AuditLogs'
        Batch            = @($Batch)
        SkipLog          = $true
    }
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
    Write-Host "Started orchestration with ID = '$InstanceId'"
} catch {
    Write-LogMessage -API 'Webhooks' -message 'Error processing webhooks' -sev Error -LogData (Get-CippException -Exception $_)
    Write-Host ( 'Webhook error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
}
