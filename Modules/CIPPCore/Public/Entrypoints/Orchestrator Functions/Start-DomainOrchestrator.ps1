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
    param($TenantFilter)
    try {

        if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
            $TenantList = @($TenantFilter)
            $TenantParams = @{
                TenantFilter = $TenantFilter
            }
        } else {
            $TenantList = Get-Tenants -IncludeAll
            if (($TenantList | Measure-Object).Count -eq 0) {
                Write-Information 'No tenants found'
                return 0
            }
            $TenantParams = @{
                IncludeAll = $true
            }
        }

        $Queue = New-CippQueueEntry -Name 'Domain Analyser' -TotalTasks ($TenantList | Measure-Object).Count
        $InputObject = [PSCustomObject]@{
            QueueFunction    = [PSCustomObject]@{
                FunctionName = 'GetTenants'
                DurableName  = 'DomainAnalyserTenant'
                QueueId      = $Queue.RowKey
                TenantParams = $TenantParams
            }
            OrchestratorName = 'DomainAnalyser_Tenants'
            SkipLog          = $true
        }
        if ($PSCmdlet.ShouldProcess('Domain Analyser', 'Starting Orchestrator')) {
            Write-LogMessage -API 'DomainAnalyser' -message 'Starting Domain Analyser' -sev Info
            return Start-CIPPOrchestrator -InputObject $InputObject
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DomainAnalyser' -message "Could not start Domain Analyser: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $false
    }
}
