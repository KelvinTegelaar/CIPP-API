param($Timer)

try {
    $CurrentlyRunning = Get-Item 'Cache_BestPracticeAnalyser\CurrentlyRunning.txt' -ErrorAction SilentlyContinue | Where-Object -Property LastWriteTime -GT (Get-Date).AddHours(-24)
    if ($CurrentlyRunning) {
        $Results = [pscustomobject]@{'Results' = 'Already running. Please wait for the current instance to finish' }
        Log-request -API 'BestPracticeAnalyser' -message 'Attempted to start analysis but an instance was already running.' -sev Info
    }
    else {
        $InstanceId = Start-NewOrchestration -FunctionName 'BestPracticeAnalyser_Orchestration'
        Write-Host "Started orchestration with ID = '$InstanceId'"
        $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Timer -InstanceId $InstanceId
        Log-request -API 'BestPracticeAnalyser' -message 'Started retrieving best practice information' -sev Info
        $Results = [pscustomobject]@{'Results' = 'Started running analysis' }
    }
    Write-Host ($Orchestrator | ConvertTo-Json)
}
catch { Write-Host "BestPracticeAnalyser_OrchestratorStarterTimer Exception $($_.Exception.Message)" }
