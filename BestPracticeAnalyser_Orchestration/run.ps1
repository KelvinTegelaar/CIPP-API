param($Context)

Log-request  -API "BestPracticeAnalyser" -tenant $tenant -message "Best Practice Analyser has Started" -sev Info
New-Item "Cache_BestPracticeAnalyser" -ItemType Directory -ErrorAction SilentlyContinue

$Batch = (Invoke-ActivityFunction -FunctionName 'BestPracticeAnalyser_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "BestPracticeAnalyser_All" -Input $item -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks

  foreach ($item in $Outputs) {
  write-host $Item | Out-String
  $Object = $Item | ConvertTo-Json

  Set-Content "Cache_BestPracticeAnalyser\$($item.tenant).BestPracticeAnalysis.json" -Value $Object -Force
}

Log-request  -API "BestPracticeAnalyser" -tenant $tenant -message "Best Practice Analyser has Finished" -sev Info