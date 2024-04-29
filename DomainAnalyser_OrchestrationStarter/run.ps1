using namespace System.Net

param($Request, $TriggerMetadata)

$Results = [pscustomobject]@{'Results' = 'Domain Analyser started' }
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
    DurableMode      = 'Sequence'
}
Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })