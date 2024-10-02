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
        $TenantList = Get-Tenants -IncludeErrors
        # Round time down to nearest minute
        $Now = Get-Date
        $StartTime = $Now.AddSeconds(-$Now.Seconds).AddMinutes(-30)
        $EndTime = $Now.AddSeconds(-$Now.Seconds)

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

        Write-Information 'Audit Logs: Creating new searches'
        foreach ($Tenant in $TenantList) {
            try {
                $NewSearch = New-CippAuditLogSearch -TenantFilter $Tenant.defaultDomainName -StartTime $StartTime -EndTime $EndTime -ProcessLogs
                Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
            } catch {
                Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
            }
        }
    } catch {
        Write-LogMessage -API 'Audit Logs' -message 'Error processing audit logs' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ( 'Audit logs error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
