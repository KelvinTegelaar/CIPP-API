param($Context)

New-Item "Cache_DomainAnalyser" -ItemType Directory -ErrorAction SilentlyContinue
New-Item "Cache_DomainAnalyser\CurrentlyRunning.txt" -ItemType File -Force
$Batch = (Invoke-ActivityFunction -FunctionName 'DomainAnalyser_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "DomainAnalyser_All" -Input $item -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Log-request -API "DomainAnalyser" -tenant $tenant -message "Outputs found count = $($Outputs.count)" -sev Info

foreach ($item in $Outputs) {
  Write-Host $Item | Out-String
  $Object = $Item | ConvertTo-Json

  Set-Content "Cache_DomainAnalyser\$($item.domain).DomainAnalysis.json" -Value $Object -Force
}

Log-request  -API "DomainAnalyser" -tenant $tenant -message "Domain Analyser has Finished" -sev Info
Remove-Item "Cache_DomainAnalyser\CurrentlyRunning.txt" -Force