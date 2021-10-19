param($Context)



$Batch = (Invoke-DurableActivity -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])"-Input $item['Tenant'] -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Write-Host $Outputs

Log-request  -API "Standards" -tenant $tenant -message "Deployment finished." -sev Info