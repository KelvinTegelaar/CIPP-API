param($tenant)
$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.ConditionalAccess
if (!$Setting) {
  $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.ConditionalAccess
}

$APINAME = "Standards"
function Remove-EmptyArrays ($Object) {
  if ($Object -is [Array]) {
    foreach ($Item in $Object) { Remove-EmptyArrays $Item }
  }
  elseif ($Object -is [HashTable]) {
    foreach ($Key in @($Object.get_Keys())) {
      if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
        $Object.Remove($Key)
      }
      else { Remove-EmptyArrays $Object[$Key] }
    }
  }
  elseif ($Object -is [PSCustomObject]) {
    foreach ($Name in @($Object.psobject.properties.Name)) {
      if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
        $Object.PSObject.Properties.Remove($Name)
      }
      elseif ($object.$name -eq $null) {
        $Object.PSObject.Properties.Remove($Name)
      }
      else { Remove-EmptyArrays $Object.$Name }
    }
  }
}




foreach ($Template in $Setting.TemplateList) {
  try {
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Template.value)'" 
    $Request = @{body = $null }
    $JSONObj = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
    Remove-EmptyArrays $JSONObj
    #Remove context as it does not belong in the payload.
    try {
      $JsonObj.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
      $JsonObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.type')
    }
    catch {
      #no action required, failure allowed.
    }
    $RawJSON = $JSONObj | Select-Object * -ExcludeProperty Id, *time* | ConvertTo-Json -Depth 10
    $PolicyName = $JSONObj.displayName
    $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -tenantid $tenant | Where-Object displayName -EQ $JSONObj.displayName
    if ($PolicyName -in $CheckExististing.displayName) {
      #patch the conditional access policy to restore our config.
      $PatchRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenant -type PATCH -body $RawJSON
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated Conditional Access Policy $($JSONObj.Displayname) to the template standard." -Sev "Info"

    }
    else {
      $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -tenantid $tenant -type POST -body $RawJSON
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($JSONObj.Displayname)" -Sev "Info"
    }
  }
  catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to create or update conditional access rule $($JSONObj.displayName): $($_.exception.message)" -sev "Error"
  }
}


