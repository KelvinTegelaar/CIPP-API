using namespace System.Net

param($Request, $TriggerMetadata)
Log-request -API "SecurityBaselines" -tenant $tenant -message "SecurityBaselines_OrchestrationStarter called at $(Get-Date)" -sev Info
$APIName = $TriggerMetadata.FunctionName
$OrchestratorName = "SecurityBaselines_Orchestration"

$CurrentlyRunning = Get-Item "SecurityBaselines_All\CurrentlyRunning.txt" -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-24)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Log-request  -API $APIName -message "Attempted to start an instance but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName $OrchestratorName
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    do {
        $StillRunning = Get-Item "SecurityBaselines_All\CurrentlyRunning.txt" -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-24)
        if (!$StillRunning) {
            $Results = Get-Content "SecurityBaselines_All\Results.json" -ErrorAction SilentlyContinue
        }
        else {
            Start-Sleep -Milliseconds 500
        }
    } while ($StillRunning)
}



Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })