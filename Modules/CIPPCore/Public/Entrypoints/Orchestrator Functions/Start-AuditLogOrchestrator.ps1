function Start-AuditLogOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Polling Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $AuditLogSearchesTable = Get-CIPPTable -TableName 'AuditLogSearches'
        $15MinutesAgo = (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $1DayAgo = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $AuditLogSearches = Get-CIPPAzDataTableEntity @AuditLogSearchesTable -Filter "(CippStatus eq 'Pending' or (CippStatus eq 'Processing' and Timestamp le datetime'$15MinutesAgo')) and Timestamp ge datetime'$1DayAgo'" -Property PartitionKey, RowKey, Tenant, CippStatus, Timestamp

        $WebhookRulesTable = Get-CIPPTable -TableName 'WebhookRules'
        $WebhookRules = Get-CIPPAzDataTableEntity @WebhookRulesTable

        if (($AuditLogSearches | Measure-Object).Count -eq 0) {
            Write-Information 'No audit log searches available'
        } elseif (($WebhookRules | Measure-Object).Count -eq 0) {
            Write-Information 'No webhook rules defined'
        } else {
            Write-Information "Audit Logs: Processing $($AuditLogSearches.Count) searches"
            if ($PSCmdlet.ShouldProcess('Start-AuditLogOrchestrator', 'Starting Audit Log Polling')) {
                $Queue = New-CippQueueEntry -Name 'Audit Log Collection' -Reference 'AuditLogCollection' -TotalTasks ($AuditLogSearches).Count
                $Batch = $AuditLogSearches | Sort-Object -Property Tenant -Unique | Select-Object @{Name = 'TenantFilter'; Expression = { $_.Tenant } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogTenant' } }

                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AuditLogs'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error processing audit logs' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
