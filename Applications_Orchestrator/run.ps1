param($Context)

$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

try {
  $Batch = (Invoke-ActivityFunction -FunctionName 'Applications_GetQueue' -Input 'LetsGo')
  Write-Host $Batch
  $ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName 'Applications_Upload' -Input $item -NoWait -RetryOptions $RetryOptions
  }

  $Outputs = Wait-ActivityFunction -Task $ParallelTasks
  Write-Host $Outputs
}
catch { 
  Write-Host "Applications_Orchestrator exception: $($_.Exception.Message)"
}
finally {
  Write-LogMessage -API 'ChocoApp' -Message 'Choco Application Queue: Deployment finished.' -sev Info
}