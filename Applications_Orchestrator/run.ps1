param($Context)

$Batch = (Invoke-DurableActivity -FunctionName 'Applications_GetQueue' -Input 'LetsGo')
write-host $Batch
$ParallelTasks = foreach ($Item in $Batch) {
    Invoke-DurableActivity -FunctionName "Applications_Upload"-Input $item -NoWait
  }

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
write-host $Outputs

Log-request "Choco Application Queue: Deployment finished." -sev Info