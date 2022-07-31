param($Context)


#$Context does not allow itself to be cast to a pscustomobject for some reason, so we converts
$context = $Context | ConvertTo-Json | ConvertFrom-Json
$GUID = $context.input.GUID
$TenantFilter = $context.input.TenantID
$APIName = $TriggerMetadata.FunctionName

$DurableRetryOptions = @{
  FirstRetryInterval  = (New-TimeSpan -Seconds 5)
  MaxNumberOfAttempts = 3
  BackoffCoefficient  = 2
}
$RetryOptions = New-DurableRetryOptions @DurableRetryOptions

Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
Write-Host 'PowerShell HTTP trigger function processed a request.'
Write-Host ($Context | ConvertTo-Json)
Write-Host "Using input $TenantFilter"
Write-Host 'starting batch'
$Batch = (Invoke-ActivityFunction -FunctionName 'Durable_AlertsQueue' -Input $TenantFilter)
Write-Host 'Stopping Batch'
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName 'Durable_AlertsFanOut' -Input $item -NoWait -RetryOptions $RetryOptions
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

$DisplayableAlerts = New-FlatArray $Outputs | Where-Object { $_.Id -ne $null } | Sort-Object -Property EventDateTime -Descending

$NewAlertsCount = $DisplayableAlerts | Where-Object { $_.Status -eq 'newAlert' } | Measure-Object | Select-Object -ExpandProperty Count
$InProgressAlertsCount = $DisplayableAlerts | Where-Object { $_.Status -eq 'inProgress' } | Measure-Object | Select-Object -ExpandProperty Count
$SeverityHighAlertsCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'high' } | Measure-Object | Select-Object -ExpandProperty Count
$SeverityMediumAlertsCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'medium' } | Measure-Object | Select-Object -ExpandProperty Count
$SeverityLowAlertsCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'low' } | Measure-Object | Select-Object -ExpandProperty Count
$SeverityInformationalCount = $DisplayableAlerts | Where-Object { ($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert') } | Where-Object { $_.Severity -eq 'informational' } | Measure-Object | Select-Object -ExpandProperty Count



$Object = [PSCustomObject]@{
  NewAlertsCount             = $NewAlertsCount
  InProgressAlertsCount      = $InProgressAlertsCount
  SeverityHighAlertsCount    = $SeverityHighAlertsCount
  SeverityMediumAlertsCount  = $SeverityMediumAlertsCount
  SeverityLowAlertsCount     = $SeverityLowAlertsCount
  SeverityInformationalCount = $SeverityInformationalCount
  MSResults                  = $DisplayableAlerts
}


New-Item 'Cache_AlertsCheck' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$Object | ConvertTo-Json -Depth 50 | Out-File "Cache_AlertsCheck\$GUID.json"