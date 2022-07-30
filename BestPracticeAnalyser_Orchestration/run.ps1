param($Context)

Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message 'Best Practice Analyser has Started' -sev Info
New-Item 'Cache_BestPracticeAnalyser' -ItemType Directory -ErrorAction SilentlyContinue
New-Item 'Cache_BestPracticeAnalyser\CurrentlyRunning.txt' -ItemType File -Force

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

$Outputs = Wait-ActivityFunction -Task $ParallelTasks

foreach ($item in $Outputs) {
  Write-Host $Item | Out-String
  $Object = $Item | ConvertTo-Json

  Set-Content "Cache_BestPracticeAnalyser\$($item.tenant).BestPracticeAnalysis.json" -Value $Object -Force
}

Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message 'Best Practice Analyser has Finished' -sev Info
Remove-Item 'Cache_BestPracticeAnalyser\CurrentlyRunning.txt' -Force