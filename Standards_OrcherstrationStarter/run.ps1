using namespace System.Net

param($Timer)

$InstanceId = Start-NewOrchestration -FunctionName 'Standards_Orchestration'
Write-Host "Started orchestration with ID = '$InstanceId'"

$Response = New-OrchestrationCheckStatusResponse -Request $timer -InstanceId $InstanceId
write-host ($Response | convertto-json)
Log-request "Standards API: Started applying the standard templates to tenants." -sev Info
