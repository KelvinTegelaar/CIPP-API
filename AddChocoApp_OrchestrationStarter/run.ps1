using namespace System.Net

param($Request, $TriggerMetadata)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Write-LogMessage  -API "ChocoApps" -message "Attempted to start upload but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'Applications_Orchestrator'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Write-LogMessage  -API "ChocoApps" -message "Started uploading applications to tenants" -sev Info
    $Results = [pscustomobject]@{"Results" = "Started application queue" }
}
Write-Host ($Orchestrator | ConvertTo-Json)


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })