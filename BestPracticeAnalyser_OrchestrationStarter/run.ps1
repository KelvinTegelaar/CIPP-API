using namespace System.Net
param($Request, $TriggerMetadata)

if ($Request.Query.TenantFilter) {
    $TenantList = @($Request.Query.TenantFilter)
    $Name = "Best Practice Analyser ($($Request.Query.TenantFilter))"
} else {
    $TenantList = Get-Tenants
    $Name = 'Best Practice Analyser (All Tenants)'
}

$BPATemplateTable = Get-CippTable -tablename 'templates'
$Filter = "PartitionKey eq 'BPATemplate'"
$Templates = ((Get-CIPPAzDataTableEntity @BPATemplateTable -Filter $Filter).JSON | ConvertFrom-Json).Name

$BPAReports = foreach ($Tenant in $TenantList) {
    foreach ($Template in $Templates) {
        [PSCustomObject]@{
            FunctionName = 'BPACollectData'
            Tenant       = $Tenant.defaultDomainName
            Template     = $Template
            QueueName    = '{0} - {1}' -f $Template, $Tenant.defaultDomainName
        }
    }
}

$Queue = New-CippQueueEntry -Name $Name -TotalTasks ($BPAReports | Measure-Object).Count
$BPAReports = $BPAReports | Select-Object *, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }
$InputObject = [PSCustomObject]@{
    Batch            = @($BPAReports)
    OrchestratorName = 'BPAOrchestrator'
    SkipLog          = $true
}
Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

$Results = [pscustomobject]@{'Results' = 'BPA started' }
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })