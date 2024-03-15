param($Timer)

$Table = Get-CIPPTable -TableName WebhookIncoming
$Webhooks = Get-CIPPAzDataTableEntity @Table
$InputObject = [PSCustomObject]@{
    OrchestratorName = 'WebhookOrchestrator'
    Batch            = @($Webhooks)
    SkipLog          = $true
}
#Write-Host ($InputObject | ConvertTo-Json)
$InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
Write-Host "Started orchestration with ID = '$InstanceId'"
#$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId