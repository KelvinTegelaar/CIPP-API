function Start-AuditLogOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Polling Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        #$webhookTable = Get-CIPPTable -tablename webhookTable
        #$Webhooks = Get-CIPPAzDataTableEntity @webhookTable -Filter "Version eq '3'" | Where-Object { $_.Resource -match '^Audit' -and $_.Status -ne 'Disabled' }
        #if (($Webhooks | Measure-Object).Count -eq 0) {
        #    Write-Information 'No webhook subscriptions found. Exiting.'
        #    return
        #}

        $StartTime = (Get-Date).AddMinutes(-15)
        $EndTime = Get-Date

        $TenantList = Get-Tenants -IncludeErrors
        $Queue = New-CippQueueEntry -Name 'Audit Log Collection' -Reference 'AuditLogCollection' -TotalTasks ($TenantList | Measure-Object).Count

        #$Batch = $Webhooks | Sort-Object -Property PartitionKey -Unique | Select-Object @{Name = 'TenantFilter'; Expression = { $_.PartitionKey } }, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }, @{Name = 'FunctionName'; Expression = { 'AuditLogTenant' } }, @{Name = 'StartTime'; Expression = { $StartTime } }, @{Name = 'EndTime'; Expression = { $EndTime } }
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'AuditLogs'
            QueueFunction    = @{
                FunctionName    = 'GetTenants'
                TenantParams    = @{
                    IncludeErrors = $true
                }
                QueueId         = $Queue.RowKey
                DurableFunction = 'AuditLogTenant'
            }
            SkipLog          = $true
        }
        if ($PSCmdlet.ShouldProcess('Start-AuditLogOrchestrator', 'Starting Audit Log Polling')) {
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        }

        foreach ($Tenant in $TenantList) {
            try {
                $null = New-CippAuditLogSearch -TenantFilter $Tenant.defaultDomainName -StartTime $StartTime -EndTime $EndTime -ProcessLogs
            } catch {
                Write-LogMessage -API 'Audit Logs' -message 'Error creating audit log search' -sev Error -LogData (Get-CippException -Exception $_)
                Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error processing audit logs' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
