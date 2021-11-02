param($Timer)

$CurrentlyRunning = Get-Item "Cache_DomainAnalyser\CurrentlyRunning.txt" -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-24)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Log-request  -API "DomainAnalyser" -message "Attempted to start analysis but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'DomainAnalyser_Orchestration'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Log-request  -API "DomainAnalyser" -message "Starting Domain Analyser" -sev Info
    $Results = [pscustomobject]@{"Results" = "Starting Domain Analyser" }
}
Write-Host ($Orchestrator | ConvertTo-Json)
