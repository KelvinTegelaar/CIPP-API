using namespace System.Net

param($Request, $TriggerMetadata)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Write-LogMessage  -API "BestPracticeAnalyser" -message "Attempted to start analysis but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'BestPracticeAnalyser_Orchestration'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Write-LogMessage  -API "BestPracticeAnalyser" -message "Started retrieving best practice information" -sev Info
    $Results = [pscustomobject]@{"Results" = "Started running analysis" }
}
Write-Host ($Orchestrator | ConvertTo-Json)


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })