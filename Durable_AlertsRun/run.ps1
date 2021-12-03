param($Context)


#$Context does not allow itself to be cast to a pscustomobject for some reason, so we converts
$context = $Context | ConvertTo-Json | ConvertFrom-Json
$GUID = $context.input.GUID
$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host ($Context | ConvertTo-Json)

$Batch = (Invoke-ActivityFunction -FunctionName 'Durable_AlertsQueue' -Input 'LetsGo')
$ParallelTasks = foreach ($Item in $Batch) {
  Invoke-DurableActivity -FunctionName "Durable_AlertsFanOut" -Input $item -NoWait
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

$DisplayableAlerts = New-FlatArray $Outputs | ? {$_.Id -ne $null} | Sort-Object -Property EventDateTime -Descending

$NewAlertsCount = $DisplayableAlerts | ? {$_.Status -eq 'newAlert'} | Measure-Object | Select-Object -ExpandProperty Count
$InProgressAlertsCount = $DisplayableAlerts | ? {$_.Status -eq 'inProgress'} | Measure-Object | Select-Object -ExpandProperty Count
$SeverityHighAlertsCount = $DisplayableAlerts | ? {($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert')} | ? {$_.Severity -eq 'high'} | Measure-Object | Select-Object -ExpandProperty Count
$SeverityMediumAlertsCount = $DisplayableAlerts | ? {($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert')} | ? {$_.Severity -eq 'medium'} | Measure-Object | Select-Object -ExpandProperty Count
$SeverityLowAlertsCount = $DisplayableAlerts | ? {($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert')} | ? {$_.Severity -eq 'low'} | Measure-Object | Select-Object -ExpandProperty Count
$SeverityInformationalCount = $DisplayableAlerts | ? {($_.Status -eq 'inProgress') -or ($_.Status -eq 'newAlert')} | ? {$_.Severity -eq 'informational'} | Measure-Object | Select-Object -ExpandProperty Count


$Object = [PSCustomObject]@{
  NewAlertsCount = $NewAlertsCount
  InProgressAlertsCount = $InProgressAlertsCount
  SeverityHighAlertsCount = $SeverityHighAlertsCount
  SeverityMediumAlertsCount = $SeverityMediumAlertsCount
  SeverityLowAlertsCount = $SeverityLowAlertsCount
  SeverityInformationalCount = $SeverityInformationalCount
  MSResults = $DisplayableAlerts
}


New-Item "Cache_AlertsCheck" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$Object | ConvertTo-Json -Depth 50 | Out-File "Cache_AlertsCheck\$GUID.json"