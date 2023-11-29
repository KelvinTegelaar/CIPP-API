param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.ConditionalAccess
if (!$Setting) {
  $Setting = ((Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.ConditionalAccess
}

$APINAME = "Standards"

foreach ($Template in $Setting.TemplateList) {
  try {
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Template.value)'" 
    $JSONObj = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON
    $CAPolicy = New-CIPPCAPolicy -TenantFilter $tenant -state $request.body.NewState -RawJSON $JSONObj -Overwrite $true -APIName $APIName -ExecutingUser $request.headers.'x-ms-client-principal'
  }
  catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to create or update conditional access rule $($JSONObj.displayName): $($_.exception.message)" -sev "Error"
  }
}


