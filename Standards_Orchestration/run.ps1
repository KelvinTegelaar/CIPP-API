param($Context)

try {
  New-Item 'Cache_Standards' -ItemType Directory -ErrorAction SilentlyContinue
  New-Item 'Cache_Standards\CurrentlyRunning.txt' -ItemType File -Force

  $Batch = (Invoke-DurableActivity -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
  $ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])"-Input $item['Tenant'] -NoWait
  }

  if (($ParallelTasks | Measure-Object).Count -gt 0) { 
    $Outputs = Wait-ActivityFunction -Task $ParallelTasks
    Write-Host $Outputs
  }
}
catch {
  Log-request -API 'Standards' -tenant $tenant -message "Orchestrator error: $($_.Exception.Message)" -sev Info
}
finally {
  Log-request -API 'Standards' -tenant $tenant -message 'Deployment finished.' -sev Info
  Remove-Item 'Cache_Standards\CurrentlyRunning.txt' -Force
}
