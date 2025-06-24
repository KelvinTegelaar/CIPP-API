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
        $APINAME,
        $tenantFilter
    )
    $APINAME = 'Set-CIPPIntunePolicy'

    $RawJSON = Get-CIPPTextReplacement -TenantFilter $tenantFilter -Text $RawJSON

    try {
        switch ($TemplateType) {
            'AppProtection' {
                $PlatformType = 'deviceAppManagement'
                $TemplateType = ($RawJSON | ConvertFrom-Json).'@odata.type' -replace '#microsoft.graph.', ''
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $displayname -Force
                $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty 'apps'
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                $TemplateTypeURL = if ($TemplateType -eq 'windowsInformationProtectionPolicy') { 'windowsInformationProtectionPolicies' } else { "$($TemplateType)s" }
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($displayname -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                }
            }
            'deviceCompliancePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceCompliancePolicies'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                $JSON = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
                $JSON.scheduledActionsForRule = @($JSON.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
                if ($displayname -in $CheckExististing.displayName) {
                    $RawJSON = ConvertTo-Json -InputObject ($JSON | Select-Object * -ExcludeProperty 'scheduledActionsForRule') -Depth 20 -Compress
                    $PostType = 'edited'
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $RawJSON = ConvertTo-Json -InputObject $JSON -Depth 20 -Compress
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'Admin' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'groupPolicyConfigurations'
                $CreateBody = '{"description":"' + $description + '","displayName":"' + $displayname + '","roleScopeTagIds":["0"]}'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($displayname -in $CheckExististing.displayName) {
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    $ExistingData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/definitionValues" -tenantid $tenantFilter
                    $DeleteJson = $RawJSON | ConvertFrom-Json -Depth 10
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'deletedIds' -Value @($ExistingData.id) -Force
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'added' -Value @() -Force
                    $DeleteJson = ConvertTo-Json -Depth 10 -InputObject $DeleteJson
                    $DeleteRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $DeleteJson
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($Displayname) to template defaults" -Sev 'info'
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $CreateBody
                    $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($Displayname) to template defaults" -Sev 'info'

                }
            }
            'Device' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceConfigurations'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value "$description" -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $displayname -Force
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName | Select-Object -Last 1
                $PolicyFile = $policyFile | Select-Object * -ExcludeProperty 'featureUpdatesWillBeRolledBack', 'qualityUpdatesWillBeRolledBack', 'qualityUpdatesPauseStartDate', 'featureUpdatesPauseStartDate'
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                if ($ExistingID) {
                    $PostType = 'edited'
                    Write-Host "Raw JSON is $RawJSON"
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev 'info'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'

                }
            }
            'Catalog' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'configurationPolicies'
                $DisplayName = ($RawJSON | ConvertFrom-Json).Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.name) {
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty Platform, PolicyType, CreationSource
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PUT -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property Name -EQ $DisplayName
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsDriverUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsDriverUpdateProfiles'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty inventorySyncStatus, newUpdates, deviceReporting, approvalType
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
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
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName

                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsQualityUpdatePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdatePolicies'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object *
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
            'windowsQualityUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdateProfiles'
                $File = ($RawJSON | ConvertFrom-Json)
                $DisplayName = $File.displayName ?? $File.Name
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                if ($DisplayName -in $CheckExististing.displayName) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty releaseDateDisplayName, deployableContentDisplayName
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $CheckExististing | Where-Object -Property displayName -EQ $displayname
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $CheckExististing | Where-Object -Property displayName -EQ $DisplayName
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev 'info'
                }
            }
        }
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "$($PostType) policy $($Displayname)" -Sev 'Info'
        if ($AssignTo) {
            Write-Host "Assigning policy to $($AssignTo) with ID $($CreateRequest.id) and type $TemplateTypeURL for tenant $tenantFilter"
            Write-Host "ID is $($CreateRequest.id)"

            Set-CIPPAssignedPolicy -GroupName $AssignTo -PolicyId $CreateRequest.id -PlatformType $PlatformType -Type $TemplateTypeURL -TenantFilter $tenantFilter -ExcludeGroup $ExcludeGroup
        }
        return "Successfully $($PostType) policy for $($tenantFilter) with display name $($Displayname)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Failed $($PostType) policy $($Displayname). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to add or set policy for $($tenantFilter) with display name $($Displayname): $($ErrorMessage.NormalizedError)"
    }
}
