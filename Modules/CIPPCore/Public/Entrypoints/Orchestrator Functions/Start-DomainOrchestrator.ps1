function Start-DomainOrchestrator {
    <#
    .SYNOPSIS
        Start the Domain Orchestrator
    .DESCRIPTION
        This function starts the Domain Orchestrator
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $TenantList = Get-Tenants -IncludeAll
        if (($TenantList | Measure-Object).Count -eq 0) {
            Write-Information 'No tenants found'
            return 0
        }

        $Queue = New-CippQueueEntry -Name 'Domain Analyser' -TotalTasks ($TenantList | Measure-Object).Count
        $InputObject = [PSCustomObject]@{
            QueueFunction    = [PSCustomObject]@{
                FunctionName = 'GetTenants'
                DurableName  = 'DomainAnalyserTenant'
                QueueId      = $Queue.RowKey
                TenantParams = @{
                    IncludeAll = $true
                }
            }
            OrchestratorName = 'DomainAnalyser_Tenants'
            SkipLog          = $true
        }
        if ($PSCmdlet.ShouldProcess('Domain Analyser', 'Starting Orchestrator')) {
            Write-LogMessage -API 'DomainAnalyser' -message 'Starting Domain Analyser' -sev Info
            return Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DomainAnalyser' -message "Could not start Domain Analyser: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $false
    }
}
