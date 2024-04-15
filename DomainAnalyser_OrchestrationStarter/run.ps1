using namespace System.Net

param($Request, $TriggerMetadata)

$Results = [pscustomobject]@{'Results' = 'Domain Analyser started' }
$InputObject = [PSCustomObject]@{
    QueueFunction    = [PSCustomObject]@{
        FunctionName = 'GetTenants'
        DurableName = 'DomainAnalyserTenant'
        TenantParams = @{
            IncludeAll = $true
        }
    }
    OrchestratorName = 'DomainAnalyser_Tenants'
    SkipLog          = $true
}
Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })