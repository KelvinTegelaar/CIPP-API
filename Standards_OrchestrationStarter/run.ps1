using namespace System.Net

param($Request, $TriggerMetadata)
$CurrentlyRunning = Get-Item "Cache_Standards\CurrentlyRunning.txt" -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-4)
if ($CurrentlyRunning) {
    $Results = [pscustomobject]@{"Results" = "Already running. Please wait for the current instance to finish" }
    Log-request  -API "StandardsApply" -message "Attempted to Standards but an instance was already running." -sev Info
}
else {
    $InstanceId = Start-NewOrchestration -FunctionName 'Standards_Orchestration'
    Write-Host "Started orchestration with ID = '$InstanceId'"
    $Response = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
    Write-Host ($Response | ConvertTo-Json)
    Log-request  -API "Standards" -tenant $tenant -message "Started applying the standard templates to tenants." -sev Info
    $Results = [pscustomobject]@{"Results" = "Started Applying Standards" }
}
Write-Host ($Orchestrator | ConvertTo-Json)


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $results
    })