param($Context)


$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions
Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Started BestPracticeAnalyser" -sev info

$Batch = (Invoke-ActivityFunction -FunctionName 'BestPracticeAnalyser_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName 'BestPracticeAnalyser_All' -Input $item -NoWait -RetryOptions $RetryOptions
}

$TableParams = Get-CippTable -tablename 'cachebpa'
$TableParams.Entity = Wait-ActivityFunction -Task $ParallelTasks
$TableParams.Force = $true
$TableParams = $TableParams | Where-Object -Property RowKey -NE "" | ConvertTo-Json -Compress
if ($TableParams) {
  try {
    Invoke-ActivityFunction -FunctionName 'Activity_AddOrUpdateTableRows' -Input $TableParams
  }
  catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Best Practice Analyser could not write to table: $($_.Exception.Message)" -sev error
  }
}
else {
  Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Tried writing empty values to BestPracticeAnalyser" -sev Info
}
Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message 'Best Practice Analyser has Finished' -sev Info