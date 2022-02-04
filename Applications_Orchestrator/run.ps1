param($Context)

$Batch = (Invoke-DurableActivity -FunctionName 'Applications_GetQueue' -Input 'LetsGo')
Write-Host $Batch
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Applications_Upload" -Input $item -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks
Write-Host $Outputs

Log-request -API "ChocoApp" -Message "Choco Application Queue: Deployment finished." -sev Info