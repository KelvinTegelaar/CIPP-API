param($TableParams)
foreach ($param in $TableParams.Entity) {
  try {
    $tableparams.entity = $param
    #Sending each item indivually, if it fails, log an error.
    Add-AzDataTableEntity @tableparams
  }
  catch {
    Write-Host ($TableParams | ConvertTo-Json)
    Write-LogMessage -API 'Activity_AddOrUpdateTableRows' -message "Unable to write to '$($TableParams.TableName)' Using RowKey $($param.RowKey) table: $($_.Exception.Message)" -sev error
  }
}
