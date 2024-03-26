param($TableParams)
$TableName = ($TableParams.Context['TableName'])
$Table = Get-CippTable -tablename $TableName

foreach ($param in $TableParams.Entity) {
  try {
    #Sending each item indivually, if it fails, log an error.
    Add-CIPPAzDataTableEntity @Table -Entity $param -Force
  }
  catch {
    Write-LogMessage -API 'Activity_AddOrUpdateTableRows' -message "Unable to write to '$($TableParams.TableName)' Using RowKey $($param.RowKey) table: $($_.Exception.Message)" -sev error
  }
}
