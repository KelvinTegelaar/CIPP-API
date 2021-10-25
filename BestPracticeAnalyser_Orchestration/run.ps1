param($Context)



$Batch = (Invoke-ActivityFunction -FunctionName 'BestPracticeAnalyser_GetQueue' -Input 'LetsGo') | Select -First 3
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "BestPracticeAnalyser_All" -Input $item -NoWait
  #Invoke-ActivityFunction -FunctionName "BestPracticeAnalyser_All" -Input $Item
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
#Write-Host $Outputs

#Write-Host "FINAL THING $($ParallelTasks | Out-String)"
#foreach ($item in $ParallelTasks) {
  foreach ($item in $Outputs) {
  write-host $Item | Out-String
  $Object = $Item | ConvertTo-Json
  Set-Content "Cache_BestPracticeAnalyser\$($item.tenant).BestPracticeAnalysis.json" -Value $Object
}




Log-request  -API "Standards" -tenant $tenant -message "$($Outputs)" -sev Info