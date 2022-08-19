param($Context)

try {

  $DurableRetryOptions = @{
    FirstRetryInterval  = (New-TimeSpan -Seconds 5)
    MaxNumberOfAttempts = 3
    BackoffCoefficient  = 2
  }
  $RetryOptions = New-DurableRetryOptions @DurableRetryOptions

  $Batch = (Invoke-ActivityFunction -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
  $ParallelTasks = foreach ($Item in $Batch) {
    if ($item['Standard']) {
      Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])" -Input $item['Tenant'] -NoWait -RetryOptions $RetryOptions
    }
  }

  if (($ParallelTasks | Measure-Object).Count -gt 0) { 
    $Outputs = Wait-ActivityFunction -Task $ParallelTasks
    Write-Host $Outputs
  }
}
catch {
  Write-LogMessage -API 'Standards' -tenant $tenant -message "Orchestrator error: $($_.Exception.Message)" -sev Info
}
finally {
  Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deployment finished.' -sev Info
}
