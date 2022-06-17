param($Context)


$Batch = (Invoke-DurableActivity -FunctionName 'Scheduler_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  try {
    Invoke-DurableActivity -FunctionName "Scheduler_$($item['Type'])" -Input $item -NoWait
  }
  catch {
    Write-Host "Could not start:"
    Write-Host ($item | ConvertTo-Json)
  }
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Write-Host $Outputs
Log-request  -API "Scheduler" -tenant $tenant -message "Scheduler Ran." -sev Debug