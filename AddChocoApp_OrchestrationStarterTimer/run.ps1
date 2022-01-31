param($Timer)

$CurrentlyRunning = Get-Item "ChocoApps.Cache\CurrentlyRunning.txt" -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-24)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Log-request  -API "ChocoApps" -message "Attempted to start upload but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'Applications_Orchestrator'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Log-request  -API "ChocoApps" -message "Started uploading applications to tenants" -sev Info
    $Results = [pscustomobject]@{"Results" = "Started running analysis" }
}
Write-Host ($Orchestrator | ConvertTo-Json)
