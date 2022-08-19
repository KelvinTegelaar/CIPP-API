param($Context)


$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

$Batch = (Invoke-ActivityFunction -FunctionName 'BestPracticeAnalyser_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName 'BestPracticeAnalyser_All' -Input $item -NoWait -RetryOptions $RetryOptions
}

$TableParams = Get-CippTable -tablename 'cachebpa'
$TableParams.Entity = Wait-ActivityFunction -Task $ParallelTasks
$TableParams.Force = $true
$TableParams = $TableParams | ConvertTo-Json -Compress
try {
  Invoke-ActivityFunction -FunctionName 'Activity_AddOrUpdateTableRows' -Input $TableParams
}
catch {
  Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Best Practice Analyser could not write to table: $($_.Exception.Message)" -sev error
}
Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message 'Best Practice Analyser has Finished' -sev Info