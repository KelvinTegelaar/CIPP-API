using namespace System.Net

param($Timer)

$InstanceId = Start-NewOrchestration -FunctionName 'Scheduler_Orchestration'
Write-Host "Started orchestration with ID = '$InstanceId'"
New-OrchestrationCheckStatusResponse -Request $timer -InstanceId $InstanceId

