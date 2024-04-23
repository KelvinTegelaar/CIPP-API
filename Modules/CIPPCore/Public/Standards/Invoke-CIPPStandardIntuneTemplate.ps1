function Invoke-CIPPStandardIntuneTemplate {
  <#
    .FUNCTIONALITY
    Internal
    #>
  param($Tenant, $Settings)
  If ($Settings.remediate) {
        
    Write-Host 'starting template deploy'
    $APINAME = 'Standards'
    foreach ($Template in $Settings.TemplateList) {
      Write-Host 'working on template deploy'
      try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'IntuneTemplate'" 
        $Request = @{body = $null }
        $Request.body = (Get-AzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($template.value)*").JSON | ConvertFrom-Json
        $displayname = $request.body.Displayname
        $description = $request.body.Description
        $RawJSON = $Request.body.RawJSON

        switch ($Request.body.Type) {
          'AppProtection' {
            $TemplateType = ($RawJSON | ConvertFrom-Json).'@odata.type' -replace '#microsoft.graph.', ''
            $TemplateTypeURL = "$($TemplateType)s"
            $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenant
            if ($displayname -in $CheckExististing.displayName) {
              $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $PolicyName
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PATCH -body $RawJSON
            } else {
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
            }
          }
          'deviceCompliancePolicies' {
            $TemplateTypeURL = 'deviceCompliancePolicies'
            $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
     
            $JSON = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
            $JSON.scheduledActionsForRule = @($JSON.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
            $RawJSON = ConvertTo-Json -InputObject $JSON -Depth 20 -Compress
            Write-Host $RawJSON
            if ($displayname -in $CheckExististing.displayName) {
              $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $PolicyName
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PATCH -body $RawJSON
            }
            $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJson
          }
          'Admin' {
            $TemplateTypeURL = 'groupPolicyConfigurations'
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
              Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated policy $($Displayname) to template defaults" -Sev 'info'

            } else {
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $CreateBody
              $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenant -type POST -body $RawJSON
              Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($Displayname) to template defaults" -Sev 'info'

            }
          }
          'Device' {
            $TemplateTypeURL = 'deviceConfigurations'
            $PolicyName = ($RawJSON | ConvertFrom-Json).displayName
            $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
            if ($PolicyName -in $CheckExististing.displayName) {
              $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $PolicyName
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PATCH -body $RawJSON
              Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated policy $($PolicyName) to template defaults" -Sev 'info'

            } else { 
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
              Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($PolicyName) via template" -Sev 'info'

            }
          }
          'Catalog' {
            $TemplateTypeURL = 'configurationPolicies'
            $PolicyName = ($RawJSON | ConvertFrom-Json).Name
            $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant
            if ($PolicyName -in $CheckExististing.name) {
              $ExistingID = $CheckExististing | Where-Object -Property Name -EQ $PolicyName
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenant -type PUT -body $RawJSON

            } else {
              $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenant -type POST -body $RawJSON
              Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added policy $($PolicyName) via template" -Sev 'info'
            }
          }

        }

        if ($Settings.AssignTo) {
          Write-Host "Assigning Policy to $($Settings.AssignTo) the create ID is $($CreateRequest)"
          if ($Settings.AssignTo -eq 'customGroup') { $Settings.AssignTo = $Settings.customGroup }
          Set-CIPPAssignedPolicy -PolicyId $CreateRequest.id -TenantFilter $tenant -GroupName $Settings.AssignTo -Type $TemplateTypeURL
        }
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully added Intune Template policy for $($Tenant)" -sev 'Info'
      } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template: $($_.exception.message)" -sev 'Error'
      }
    }
  }
}
