function Start-AuditLogOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Polling Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $AuditLogSearchesTable = Get-CIPPTable -TableName 'AuditLogSearches'
        $AuditLogSearches = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "CippStatus eq 'Pending'"

        if (($AuditLogSearches | Measure-Object).Count -eq 0) {
            Write-Information 'No audit log searches available'
        } else {
            $Queue = New-CippQueueEntry -Name 'Audit Log Collection' -Reference 'AuditLogCollection' -TotalTasks ($AuditLogSearches).Count
            $Batch = $AuditLogSearches | Sort-Object -Property Tenant -Unique | Select-Object @{Name = 'TenantFilter'; Expression = { $_.Tenant } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogTenant' } }

            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'AuditLogs'
                Batch            = @($Batch)
                SkipLog          = $true
            }
            if ($PSCmdlet.ShouldProcess('Start-AuditLogOrchestrator', 'Starting Audit Log Polling')) {
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error processing audit logs' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
