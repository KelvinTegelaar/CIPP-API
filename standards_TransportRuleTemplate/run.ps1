param($tenant)


$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.TransportRuleTemplate
if (!$Setting) {
  $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.TransportRuleTemplate
}

foreach ($Template in $Setting.TemplateList) {
  $Table = Get-CippTable -tablename 'templates'
  $Filter = "PartitionKey eq 'TransportTemplate' and RowKey eq '$($Template.value)'" 
  $RequestParams = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
  $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $Tenant -cmdlet "Get-TransportRule" -useSystemMailbox $true | Where-Object -Property Identity -EQ $RequestParams.name
  
  
  try {
    if ($Existing) {
      Write-Host "Found existing"
      $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
      $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "Set-TransportRule" -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty UseLegacyRegex) -useSystemMailbox $true
      Write-LogMessage -API "Standards" -tenant $tenant -message "Successfully set transport rule for $tenant"
    }
    else {
      Write-Host "Creating new"
      $GraphRequest = New-ExoRequest -tenantid $Tenant -cmdlet "New-TransportRule" -cmdParams $RequestParams -useSystemMailbox $true
      Write-LogMessage -API "Standards" -tenant $tenant -message "Successfully created transport rule for $tenant"
    }
        
    Write-LogMessage -API $APINAME -tenant $Tenant -message "Created transport rule for $($tenantfilter)" -sev Debug
  }
  catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message   "Could not create transport rule for $($tenantfilter): $($_.Exception.message)"
  }
}