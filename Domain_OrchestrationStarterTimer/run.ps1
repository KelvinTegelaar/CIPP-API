param($Timer)

if ($env:DEV_SKIP_DOMAIN_TIMER) {
    Write-Host 'Skipping DomainAnalyser timer'
    exit 0
}

try {
    if ($CurrentlyRunning) {
        $Results = [pscustomobject]@{'Results' = 'Already running. Please wait for the current instance to finish' }
        Write-LogMessage -API 'DomainAnalyser' -message 'Attempted to start analysis but an instance was already running.' -sev Info
    } else {
        #$InstanceId = Start-NewOrchestration -FunctionName 'DomainAnalyser_Orchestration'
        Write-Host "Started orchestration with ID = '$InstanceId'"
        #Orchestrator = New-OrchestrationCheckStatusResponse -Request $Timer -InstanceId $InstanceId
        Write-LogMessage -API 'DomainAnalyser' -message 'Starting Domain Analyser' -sev Info
        $Results = [pscustomobject]@{'Results' = 'Starting Domain Analyser' }

        $TenantList = Get-Tenants -IncludeAll
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
        Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
    }
    Write-Host ($Orchestrator | ConvertTo-Json)
} catch { Write-Host "Domain_OrchestratorStarterTimer Exception $($_.Exception.Message)" }