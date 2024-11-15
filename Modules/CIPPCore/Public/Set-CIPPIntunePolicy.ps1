function Set-CIPPIntunePolicy {
    param (
        [Parameter(Mandatory = $true)]
        $TemplateType,
        $Description,
        $DisplayName,
        $RawJSON,
        $AssignTo,
        $ExecutingUser,
        $tenantFilter
    )
    $ReturnValue = try {
        switch ($TemplateType) {
            'AppProtection' {
                $TemplateType = ($RawJSON | ConvertFrom-Json).'@odata.type' -replace '#microsoft.graph.', ''
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $displayname -Force
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                $TemplateTypeURL = if ($TemplateType -eq 'windowsInformationProtectionPolicy') { 'windowsInformationProtectionPolicies' } else { "$($TemplateType)s" }
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenantFilter
                if ($displayname -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                }
            }
            'deviceCompliancePolicies' {
                $TemplateTypeURL = 'deviceCompliancePolicies'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter
                $JSON = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
                $JSON.scheduledActionsForRule = @($JSON.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
                if ($displayname -in $CheckExististing.displayName) {
                    $RawJSON = ConvertTo-Json -InputObject ($JSON | Select-Object * -ExcludeProperty 'scheduledActionsForRule') -Depth 20 -Compress
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $RawJSON = ConvertTo-Json -InputObject $JSON -Depth 20 -Compress
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'Admin' {
                $TemplateTypeURL = 'groupPolicyConfigurations'
                $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter
                if ($displayname -in $CheckExististing.displayName) {
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $ExistingData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($ExistingID.id)')/definitionValues" -tenantid $tenantFilter
                    $DeleteJson = $RawJSON | ConvertFrom-Json -Depth 10
                    $DeleteJson.deletedIds = @($ExistingData.id)
                    $DeleteJson.added = @()
                    $DeleteJson = ConvertTo-Json -Depth 10 -InputObject $DeleteJson
                    $DeleteRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $DeleteJson
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($Displayname) to template defaults" -Sev 'info'
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $CreateBody
                    $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Added policy $($Displayname) to template defaults" -Sev 'info'

                }
            }
            'Device' {
                $TemplateTypeURL = 'deviceConfigurations'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value "$description" -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $displayname -Force
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter
                if ($PolicyFile.displayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'

                }
            }
            'Catalog' {
                $TemplateTypeURL = 'configurationPolicies'
                $DisplayName = ($RawJSON | ConvertFrom-Json).Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.name) {
                    $ExistingID = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PUT -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsDriverUpdateProfiles' {
                $TemplateTypeURL = 'windowsDriverUpdateProfiles'
                $DisplayName = ($RawJSON | ConvertFrom-Json).Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.name) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PUT -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName

                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }

        }
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($tenantFilter) -message "$($PostType) policy $($Displayname)" -Sev 'Info'
        if ($AssignTo) {
            Write-Host "Assigning policy to $($AssignTo) with ID $($CreateRequest.id) and type $TemplateTypeURL for tenant $tenantFilter"
            Write-Host "ID is $($CreateRequest.id)"
            Set-CIPPAssignedPolicy -GroupName $AssignTo -PolicyId $CreateRequest.id -Type $TemplateTypeURL -TenantFilter $tenantFilter
        }
        return "Successfully $($PostType) policy for $($tenantFilter) with display name $($Displayname)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($tenantFilter) -message "Failed $($PostType) policy $($Displayname). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to add or set policy for $($tenantFilter) with display name $($Displayname): $($ErrorMessage.NormalizedError)"
    }

}
