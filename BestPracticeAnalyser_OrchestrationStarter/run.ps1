using namespace System.Net

param($Request, $TriggerMetadata)

$InstanceId = Start-NewOrchestration -FunctionName 'BestPracticeAnalyser_Orchestration'
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId

Write-Host ($Response | ConvertTo-Json)

Log-request  -API "Standards" -tenant $tenant -message "Started applying the standard templates to tenants." -sev Info
