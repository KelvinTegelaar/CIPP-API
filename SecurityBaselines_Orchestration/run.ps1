param($Context)

Log-request -API "SecurityBaselines" -tenant $tenant -message "SecurityBaselines_Orchestration called at $((Get-Date).tofiletime())" -sev Info
#Remove-Item "SecurityBaselines_All\results.json" -Force

New-Item "SecurityBaselines_All\CurrentlyRunning.txt" -ItemType File -Force
$Batch = Get-Tenants
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "SecurityBaselines_All" -Input $item -NoWait
}

Log-request -API "SecurityBaselines" -tenant $tenant -message "STARTING PROCESS OF OUTPUTS!" -sev Info
$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Log-request -API "SecurityBaselines" -tenant $tenant -message "Outputs found count = $($Outputs.count)" -sev Info

foreach ($item in $Outputs) {
  Write-Host $Item | Out-String
  $Object = $Item | ConvertTo-Json

  Set-Content "SecurityBaselines_All\results.json" -Value $Object -Force
}

#Log-request  -API "DomainAnalyser" -tenant $tenant -message "Domain Analyser has Finished" -sev Info
Remove-Item "SecurityBaselines_All\CurrentlyRunning.txt" -Force