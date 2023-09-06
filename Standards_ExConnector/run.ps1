param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.ExConnector
if (!$Setting) {
  $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.ExConnector
}
$APINAME = "Standards"
foreach ($Template in $Setting.TemplateList) {
  try {
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'ExConnectorTemplate' and RowKey eq '$($Template.value)'" 
    $connectorType = (Get-AzDataTableEntity @Table -Filter $Filter).direction
    $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
    $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet "Get-$($ConnectorType)connector" | Where-Object -Property Identity -EQ $RequestParams.name
    if ($Existing) {
      $RequestParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
      $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "Set-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
      Write-LogMessage -API $APINAME -tenant $Tenant -message "Updated transport rule for $($Tenant)" -sev info
    }
    else {
      $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
      Write-LogMessage -API $APINAME -tenant $Tenant -message "Created transport rule for $($Tenant)" -sev info
    }
  }
  catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to create or update Exchange Connector Rule: $($_.exception.message)" -sev "Error"
  }

}

