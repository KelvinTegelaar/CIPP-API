param($Context)
#$Context does not allow itself to be cast to a pscustomobject for some reason, so we converts
$context = $Context | ConvertTo-Json | ConvertFrom-Json
$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host ($Context | ConvertTo-Json)

$Batch = (Invoke-ActivityFunction -FunctionName 'Durable_AlertsQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Durable_AlertsFanOut" -Input $item -NoWait
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks


New-Item "Cache_AlertsCheck" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$results | ConvertTo-Json | Out-File "Cache_BECCheck\$GUID.json"