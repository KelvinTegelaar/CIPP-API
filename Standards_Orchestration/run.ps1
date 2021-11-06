param($Context)

New-Item "Cache_Standards" -ItemType Directory -ErrorAction SilentlyContinue
New-Item "Cache_Standards\CurrentlyRunning.txt" -ItemType File -Force

$Batch = (Invoke-DurableActivity -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])"-Input $item['Tenant'] -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Write-Host $Outputs
Remove-Item "Cache_Standards\CurrentlyRunning.txt" -Force
Log-request  -API "Standards" -tenant $tenant -message "Deployment finished." -sev Info