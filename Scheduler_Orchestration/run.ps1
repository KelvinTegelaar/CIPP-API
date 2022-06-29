param($Context)

try {
  $Batch = (Invoke-DurableActivity -FunctionName 'Scheduler_GetQueue' -Input 'LetsGo')

  if (($Batch | Measure-Object).Count -gt 0) {
    $ParallelTasks = foreach ($Item in $Batch) {
      try {
        Invoke-DurableActivity -FunctionName "Scheduler_$($item['Type'])" -Input $item -NoWait
      }
      catch {
        Write-Host 'Could not start:'
        Write-Host ($item | ConvertTo-Json)
      }
    }
    $Outputs = Wait-ActivityFunction -Task $ParallelTasks
  }

  Write-Host $Outputs
}
catch {}
finally {
  Log-request -API 'Scheduler' -tenant $tenant -message 'Scheduler Ran.' -sev Debug
}