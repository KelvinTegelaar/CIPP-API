using namespace System.Net

param($Timer)

$InstanceId = Start-NewOrchestration -FunctionName 'Standards_Orchestration'
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-OrchestrationCheckStatusResponse -Request $timer -InstanceId $InstanceId
Write-Host ($Response | ConvertTo-Json)
Log-request  -API "Standards" -tenant $tenant -message "Started applying the standard templates to tenants." -sev Info
