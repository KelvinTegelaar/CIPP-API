using namespace System.Net

param($Request, $TriggerMetadata)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Write-LogMessage  -API "StandardsApply" -message "Attempted to Standards but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'Standards_Orchestration'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Response = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Write-Host ($Response | ConvertTo-Json)
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Started applying the standard templates to tenants." -sev Info
    $Results = [pscustomobject]@{"Results" = "Started Applying Standards" }
}
Write-Host ($Orchestrator | ConvertTo-Json)


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })