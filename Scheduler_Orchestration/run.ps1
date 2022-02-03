param($Context)

New-Item "Cache_Scheduler" -ItemType Directory -ErrorAction SilentlyContinue
New-Item "Cache_Scheduler\CurrentlyRunning.txt" -ItemType File -Force


$Batch = (Invoke-DurableActivity -FunctionName 'Scheduler_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Scheduler_$($item['Type'])" -Input $item['Tenant'] -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Write-Host $Outputs
Remove-Item "Cache_Scheduler\CurrentlyRunning.txt" -Force
Log-request  -API "Scheduler" -tenant $tenant -message "Scheduler Ran." -sev Info