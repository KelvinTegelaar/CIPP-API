param($Context)


#$Context does not allow itself to be cast to a pscustomobject for some reason, so we converts
$context = $Context | ConvertTo-Json | ConvertFrom-Json
$GUID = $context.input.GUID
$TenantFilter = $context.input.TenantID
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
Write-Host 'PowerShell HTTP trigger function processed a request.'
Write-Host ($Context | ConvertTo-Json)
Write-Host "Using input $TenantFilter"
Write-Host 'starting batch'

$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

$Batch = (Invoke-ActivityFunction -FunctionName 'Durable_AlertsQueue' -Input $TenantFilter)
Write-Host 'Stopping Batch'
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName 'Durable_IncidentsFanOut' -Input $item -NoWait -RetryOptions $RetryOptions
}

$Outputs = Wait-ActivityFunction -Task $ParallelTasks

function New-FlatArray ([Array]$arr) {
  $arr | ForEach-Object {
    if ($_ -is 'Array') {
      New-FlatArray $_
    }
    else { $_ }
  }
}

$DisplayableIncidents = New-FlatArray $Outputs | Where-Object { $_.Id -ne $null } | Sort-Object -Property EventDateTime -Descending



$Object = [PSCustomObject]@{
  MSResults = $DisplayableIncidents
}


New-Item 'Cache_IncidentsCheck' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$Object | ConvertTo-Json -Depth 50 | Out-File "Cache_IncidentsCheck\$GUID.json"