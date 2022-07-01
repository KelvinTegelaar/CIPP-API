param($Context)

try {
  $Batch = (Invoke-DurableActivity -FunctionName 'Applications_GetQueue' -Input 'LetsGo')
  Write-Host $Batch
  $ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName 'Applications_Upload' -Input $item -NoWait
  }

  $Outputs = Wait-ActivityFunction -Task $ParallelTasks
  Write-Host $Outputs
}
catch { 
  Write-Host "Applications_Orchestrator exception: $($_.Exception.Message)"
}
finally {
  Log-request -API 'ChocoApp' -Message 'Choco Application Queue: Deployment finished.' -sev Info
}