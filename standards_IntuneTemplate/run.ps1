param($tenant)

$ConfigTable = Get-CippTable -tablename 'standards'
$Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq '$tenant'").JSON | ConvertFrom-Json).standards.IntuneTemplate
if (!$Setting) {
  $Setting = ((Get-AzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'standards' and RowKey eq 'AllTenants'").JSON | ConvertFrom-Json).standards.IntuneTemplate
}

$APINAME = "Standards"
foreach ($Template in $Setting.TemplateList) {
  try {
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'" 
    $Request = @{body = $null }
    $Request.body = (Get-AzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($template.value)*").JSON | ConvertFrom-Json
    $displayname = $request.body.Displayname
    $description = $request.body.Description
    $AssignTo = if ($request.body.Assignto -ne "on") { $request.body.Assignto }
    $RawJSON = $Request.body.RawJSON

    switch ($Request.body.Type) {
      "Admin" {
        $TemplateTypeURL = "groupPolicyConfigurations"
        $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
        if ($displayname -in $CheckExististing.displayName) {
          $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
          $ExistingData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($existingId.id)')/definitionValues" -tenantid $tenant
          $DeleteJson = $RawJSON | ConvertFrom-Json -Depth 10
          $DeleteJson.deletedIds = @($ExistingData.id)
          $DeleteJson.added = @()
          $DeleteJson = ConvertTo-Json -Depth 10 -InputObject $DeleteJson
          $DeleteRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($existingId.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $DeleteJson
          $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($existingId.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated policy $($Displayname) to template defaults" -Sev "info"

        }
        else {
          $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $CreateBody
          $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname) to template defaults" -Sev "info"

        }
      }
      "Device" {
        $TemplateTypeURL = "deviceConfigurations"
        $PolicyName = ($RawJSON | ConvertFrom-Json).displayName
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
        if ($PolicyName -in $CheckExististing.displayName) {
          $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $PolicyName
          $PatchRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PATCH -body $RawJSON
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated policy $($PolicyName) to template defaults" -Sev "info"

        }
        else { 
          $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($PolicyName) via template" -Sev "info"

        }
      }
      "Catalog" {
        $TemplateTypeURL = "configurationPolicies"
        $PolicyName = ($RawJSON | ConvertFrom-Json).Name
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
        if ($PolicyName -in $CheckExististing.name) {
          $ExistingID = $CheckExististing | Where-Object -Property Name -EQ $PolicyName
          $PUTRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PUT -body $RawJSON

        }
        else {
          $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
          Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($PolicyName) via template" -Sev "info"

        }
      }

    }
    if ($AssignTo) {
      $AssignBody = if ($AssignTo -ne "AllDevicesAndUsers") { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
      $assign = New-GraphPOSTRequest -uri  "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $AssignTo" -Sev "Info"
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Successfully added Intune Template policy for $($Tenant)" -sev "Info"
  }
  catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to create or update Intune Template: $($_.exception.message)" -sev "Error"
  }
}