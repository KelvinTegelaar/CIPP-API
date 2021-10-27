using namespace System.Net

param($Request, $TriggerMetadata)

$CurrentlyRunning = Test-Path "Cache_BestPracticeAnalyser\CurrentlyRunning.txt" | Where-Object -Property LastWriteTime -GT (Get-Date).addhours(-24)
if ($CurrentlyRunning -eq $false) {
    $InstanceId = Start-NewOrchestration -FunctionName 'BestPracticeAnalyser_Orchestration'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Log-request  -API "BestPracticeAnalyser" -message "Started retrieving best practice information" -sev Info
    $Results = [pscustomobject]@{"Results" = "Started running analysis" }
}
else {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Log-request  -API "BestPracticeAnalyser" -message "Attempted to start analysis but an instance was already running." -sev Info

}
Write-Host ($Orchestrator | ConvertTo-Json)


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })