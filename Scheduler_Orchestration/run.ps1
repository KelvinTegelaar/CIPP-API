param($Context)

$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

try {
  $Batch = Invoke-ActivityFunction -FunctionName 'Scheduler_GetQueue' -Input 'LetsGo'
  if (($Batch | Measure-Object).Count -gt 0) {

    $ParallelTasks = foreach ($Item in $Batch) {
      try {
        Invoke-DurableActivity -FunctionName "Scheduler_$($item['Type'])" -Input $item -NoWait -RetryOptions $RetryOptions -ErrorAction Stop
      }
      catch {
        Write-Host 'Could not start:'
        Write-Host ($item | ConvertTo-Json)
      }
    }
    $Outputs = Wait-ActivityFunction -Task $ParallelTasks
    if (-not $Outputs['DataReturned']) {
      Write-Host 'Errors detected'
    }
  }
}
catch {}
finally {
  Write-LogMessage -API 'Scheduler' -tenant $tenant -message 'Scheduler Ran.' -sev Debug
}