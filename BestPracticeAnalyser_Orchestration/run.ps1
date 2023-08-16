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

Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message 'Best Practice Analyser has Finished' -sev Info