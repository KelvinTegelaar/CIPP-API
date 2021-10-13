param($Context)



$Batch = (Invoke-DurableActivity -FunctionName 'Standards_GetQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName "Standards_$($item['Standard'])"-Input $item['Tenant'] -NoWait
  }

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
write-host $Outputs

Log-request "Standards API: Deployment finished." -sev Info