param($TableParams)

try {
  Add-AzDataTableEntity @TableParams
}
catch {
  Write-LogMessage -API 'Activity_AddOrUpdateTableRows' -message "Unable to write to '$($TableParams.TableName)' table: $($_.Exception.Message)" -sev error
}
