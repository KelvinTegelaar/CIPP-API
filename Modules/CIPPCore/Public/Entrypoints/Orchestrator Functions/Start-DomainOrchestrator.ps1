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
    param(
        $TenantFilter,
        [switch]$SkipExchangeFilter
    )
    try {

        if ($TenantFilter -and $TenantFilter -ne 'allTenants') {
            $Queue = New-CippQueueEntry -Name 'Domain Analyser' -TotalTasks 1
            $InputObject = [PSCustomObject]@{
                QueueFunction    = [PSCustomObject]@{
                    FunctionName = 'GetTenants'
                    DurableName  = 'DomainAnalyserTenant'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        TenantFilter = $TenantFilter
                    }
                }
                OrchestratorName = 'DomainAnalyser_Tenants'
                SkipLog          = $true
            }
        } else {
            $TenantList = @(Get-Tenants)
            if (-not $SkipExchangeFilter) {
                $ExchangeCapabilities = @(
                    'EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE'
                    'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV'
                    'EXCHANGE_LITE'
                    'EXCHANGE_S_DESKLESS', 'EXCHANGE_S_DESKLESS_GOV'
                    'EXCHANGE_S_ESSENTIALS'
                )
                $TenantList = @($TenantList | Where-Object {
                        Test-CIPPStandardLicense -StandardName 'DomainAnalyser' -TenantFilter $_.defaultDomainName -RequiredCapabilities $ExchangeCapabilities -SkipLog
                    })
            }
            if ($TenantList.Count -eq 0) {
                Write-Information 'No tenants to analyse'
                return 0
            }

            $Queue = New-CippQueueEntry -Name 'Domain Analyser' -TotalTasks $TenantList.Count
            $Batch = foreach ($Tenant in $TenantList) {
                [PSCustomObject]@{
                    customerId   = $Tenant.customerId
                    FunctionName = 'DomainAnalyserTenant'
                    QueueId      = $Queue.RowKey
                    QueueName    = $Tenant.defaultDomainName
                }
            }
            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = 'DomainAnalyser_Tenants'
                SkipLog          = $true
            }
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
