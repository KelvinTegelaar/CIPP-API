param($Context)

$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

$Batch = (Invoke-ActivityFunction -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  if ($item['Standard']) {
    try {
      Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])" -Input "$($item['Tenant'])" -NoWait -RetryOptions $RetryOptions
    }
    catch {
      Write-LogMessage -API 'Standards' -tenant $tenant -message "Task error: $($_.Exception.Message)" -sev Error

    }
  }
}

if (($ParallelTasks).count -gt 0) { 
  $Outputs = Wait-ActivityFunction -Task $ParallelTasks
  Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deployment finished.' -sev Info
}
