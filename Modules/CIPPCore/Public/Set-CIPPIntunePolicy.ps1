function Set-CIPPIntunePolicy {
    param (
        [Parameter(Mandatory = $true)]
        $TemplateType,
        $Description,
        $DisplayName,
        $RawJSON,
        $AssignTo,
        $ExcludeGroup,
        $Headers,
        $APIName = 'Set-CIPPIntunePolicy',
        $TenantFilter,
        $AssignmentFilterName,
        $AssignmentFilterType = 'include'
    )

    $RawJSON = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $RawJSON

    try {
        switch ($TemplateType) {
            'AppProtection' {
                $PlatformType = 'deviceAppManagement'
                $TemplateType = ($RawJSON | ConvertFrom-Json).'@odata.type' -replace '#microsoft.graph.', ''
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty 'apps'
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                $TemplateTypeURL = if ($TemplateType -eq 'windowsInformationProtectionPolicy') { 'windowsInformationProtectionPolicies' } else { "$($TemplateType)s" }
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                }
            }
            'AppConfiguration' {
                $PlatformType = 'deviceAppManagement'
                $TemplateTypeURL = 'mobileAppConfigurations'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context', targetedMobileApps
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20 -Compress
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context'
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20 -Compress
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'deviceCompliancePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceCompliancePolicies'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $JSON = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
                $JSON.scheduledActionsForRule = @($JSON.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
                if ($DisplayName -in $CheckExististing.displayName) {
                    $RawJSON = ConvertTo-Json -InputObject ($JSON | Select-Object * -ExcludeProperty 'scheduledActionsForRule') -Depth 20 -Compress
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $RawJSON = ConvertTo-Json -InputObject $JSON -Depth 20 -Compress
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'Admin' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'groupPolicyConfigurations'
                $CreateBody = '{"description":"' + $Description + '","displayName":"' + $DisplayName + '","roleScopeTagIds":["0"]}'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    $ExistingData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/definitionValues" -tenantid $TenantFilter
                    $DeleteJson = $RawJSON | ConvertFrom-Json -Depth 10
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'deletedIds' -Value @($ExistingData.id) -Force
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'added' -Value @() -Force
                    $DeleteJson = ConvertTo-Json -Depth 10 -InputObject $DeleteJson
                    $DeleteRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $DeleteJson
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $CreateBody
                    $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) to template defaults" -Sev 'info'

                }
            }
            'Device' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceConfigurations'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value "$Description" -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName | Select-Object -Last 1
                $PolicyFile = $policyFile | Select-Object * -ExcludeProperty 'featureUpdatesWillBeRolledBack', 'qualityUpdatesWillBeRolledBack', 'qualityUpdatesPauseStartDate', 'featureUpdatesPauseStartDate'
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                if ($ExistingID) {
                    $PostType = 'edited'
                    Write-Host "Raw JSON is $RawJSON"
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'

                }
            }
            'Catalog' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'configurationPolicies'
                $DisplayName = ($RawJSON | ConvertFrom-Json).Name

                $Template = $RawJSON | ConvertFrom-Json
                if ($Template.templateReference.templateId) {
                    Write-Information "Checking configuration policy template $($Template.templateReference.templateId) for $($DisplayName)"
                    # Remove unavailable settings from the template
                    $AvailableSettings = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates('$($Template.templateReference.templateId)')/settingTemplates?`$expand=settingDefinitions&`$top=1000" -tenantid $tenantFilter

                    if ($AvailableSettings) {
                        Write-Information "Available settings for template $($Template.templateReference.templateId): $($AvailableSettings.Count)"
                        $FilteredSettings = [System.Collections.Generic.List[psobject]]::new()
                        foreach ($setting in $Template.settings) {
                            if ($setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId -in $AvailableSettings.settingInstanceTemplate.settingInstanceTemplateId) {
                                $AvailableSetting = $AvailableSettings | Where-Object { $_.settingInstanceTemplate.settingInstanceTemplateId -eq $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId }

                                if ($AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId -cnotmatch $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId) {
                                    # update casing
                                    Write-Information "Fixing casing for setting instance template $($AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId)"
                                    $setting.settingInstance.settingInstanceTemplateReference.settingInstanceTemplateId = $AvailableSetting.settingInstanceTemplate.settingInstanceTemplateId
                                }

                                if ($AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate -cnotmatch $setting.settingInstance.choiceSettingValue.settingValueTemplateReference.settingValueTemplateId) {
                                    # update choice setting value template
                                    Write-Information "Fixing casing for choice setting value template $($AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate.settingValueTemplateId)"
                                    $setting.settingInstance.choiceSettingValue.settingValueTemplateReference.settingValueTemplateId = $AvailableSetting.settingInstanceTemplate.choiceSettingValueTemplate.settingValueTemplateId
                                }

                                $FilteredSettings.Add($setting)
                            }
                        }
                        $Template.settings = $FilteredSettings
                        $RawJSON = $Template | ConvertTo-Json -Depth 100 -Compress
                    }
                }

                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.name) {
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty Platform, PolicyType, CreationSource
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PUT -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsDriverUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsDriverUpdateProfiles'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty inventorySyncStatus, newUpdates, deviceReporting, approvalType
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsFeatureUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsFeatureUpdateProfiles'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty deployableContentDisplayName, endOfSupportDate, installLatestWindows10OnWindows11IneligibleDevice
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName

                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsQualityUpdatePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdatePolicies'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object *
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsQualityUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdateProfiles'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty releaseDateDisplayName, deployableContentDisplayName
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "$($PostType) policy $($DisplayName)" -Sev 'Info'
        if ($AssignTo) {
            Write-Host "Assigning policy to $($AssignTo) with ID $($CreateRequest.id) and type $TemplateTypeURL for tenant $TenantFilter"
            Write-Host "ID is $($CreateRequest.id)"

            $AssignParams = @{
                GroupName    = $AssignTo
                PolicyId     = $CreateRequest.id
                PlatformType = $PlatformType
                Type         = $TemplateTypeURL
                TenantFilter = $tenantFilter
                ExcludeGroup = $ExcludeGroup
            }

            if ($AssignmentFilterName) {
                $AssignParams.AssignmentFilterName = $AssignmentFilterName
                $AssignParams.AssignmentFilterType = $AssignmentFilterType
            }

            Set-CIPPAssignedPolicy @AssignParams
        }
        return "Successfully $($PostType) policy for $($TenantFilter) with display name $($DisplayName)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed $($PostType) policy $($DisplayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to add or set policy for $($TenantFilter) with display name $($DisplayName): $($ErrorMessage.NormalizedError)"
    }
}
