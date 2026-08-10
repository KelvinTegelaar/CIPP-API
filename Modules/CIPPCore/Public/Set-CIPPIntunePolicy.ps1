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
        $AssignmentFilterType = 'include',
        [array]$ReusableSettings,
        [int]$LevenshteinDistance = 0,
        # 'append' (default) adds the requested assignments and leaves everything else in place.
        # 'replace' makes the policy's assignments exactly what was requested - used by callers that
        # own the assignment, so that a comparison demanding an exact set is actually satisfiable.
        [ValidateSet('append', 'replace')]
        [string]$AssignmentMode = 'append'
    )

    $RawJSON = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $RawJSON -EscapeForJson

    if ($LevenshteinDistance -gt 5) {
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "LevenshteinDistance is set to $LevenshteinDistance. Values above 5 can match unrelated policies; use with caution." -Sev Warning
    }

    try {
        switch ($TemplateType) {
            'AppProtection' {
                $PlatformType = 'deviceAppManagement'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $TemplateTypeURL = Get-CIPPAppProtectionPolicyUrl -Policy $PolicyFile
                if (-not $TemplateTypeURL) {
                    throw "App Protection template '$DisplayName' identifies no platform - it carries no @odata.type, no @odata.context and no platform-specific settings - so the policy type cannot be determined. Recreate the template or re-run the template sync."
                }
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                # Read-only properties Graph echoes back on a GET. They are carried in the template
                # because the capture keeps the payload whole, and Graph rejects them on the way in.
                $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty 'apps', id, createdDateTime, lastModifiedDateTime, version, '@odata.context', isAssigned, deployedAppCount
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
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
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context', targetedMobileApps
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20 -Compress
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev Info
                    $CreateRequest = $FuzzyResult.Policy
                } else {
                    $PostType = 'added'
                    $PolicyFile = $PolicyFile | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context'
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20 -Compress
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'deviceCompliancePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceCompliancePolicies'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, 'scheduledActionsForRule@odata.context', '@odata.context'
                $PolicyFile.scheduledActionsForRule = @($PolicyFile.scheduledActionsForRule | Select-Object * -ExcludeProperty 'scheduledActionConfigurations@odata.context')
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value $Description -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                $ComplianceODataType = ($RawJSON | ConvertFrom-Json).'@odata.type'
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance -ODataType $ComplianceODataType
                if ($FuzzyResult) {
                    $RawJSON = ConvertTo-Json -InputObject ($PolicyFile | Select-Object * -ExcludeProperty 'scheduledActionsForRule') -Depth 20 -Compress
                    $PostType = 'edited'
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev Info
                    $CreateRequest = $FuzzyResult.Policy
                } else {
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 20 -Compress
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'Admin' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'groupPolicyConfigurations'
                $CreateBody = '{"description":"' + $Description + '","displayName":"' + $DisplayName + '","roleScopeTagIds":["0"]}'
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    $ExistingData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/definitionValues" -tenantid $TenantFilter
                    $DeleteJson = $RawJSON | ConvertFrom-Json -Depth 10
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'deletedIds' -Value @($ExistingData.id) -Force
                    $DeleteJson | Add-Member -MemberType NoteProperty -Name 'added' -Value @() -Force
                    $DeleteJson = ConvertTo-Json -Depth 10 -InputObject $DeleteJson
                    $DeleteRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $DeleteJson
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($ExistingID.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev Info
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $CreateBody
                    $UpdateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($CreateRequest.id)')/updateDefinitionValues" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) to template defaults" -Sev Info

                }
            }
            'Device' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceConfigurations'
                $PolicyFile = $RawJSON | ConvertFrom-Json
                $Null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'description' -Value "$Description" -Force
                $null = $PolicyFile | Add-Member -MemberType NoteProperty -Name 'displayName' -Value $DisplayName -Force
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $DeviceODataType = $PolicyFile.'@odata.type'
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance -ODataType $DeviceODataType
                $PolicyFile = $policyFile | Select-Object * -ExcludeProperty 'featureUpdatesWillBeRolledBack', 'qualityUpdatesWillBeRolledBack', 'qualityUpdatesPauseStartDate', 'featureUpdatesPauseStartDate'
                $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    Write-Host "Raw JSON is $RawJSON"
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $tenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($tenantFilter) -message "Updated policy $($DisplayName) to template defaults" -Sev Info
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($tenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info

                }
            }
            'Catalog' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'configurationPolicies'
                $DisplayName = Get-CIPPIntunePolicyName -TemplateType 'Catalog' -RawJSON $RawJSON -DisplayName $DisplayName
                if ($ReusableSettings) {
                    Write-Verbose "Catalog: ReusableSettings count $($ReusableSettings.Count)"
                    Write-Verbose ('Catalog: ReusableSettings detail ' + ($ReusableSettings | ConvertTo-Json -Depth 5 -Compress))
                    $syncResult = Sync-CIPPReusablePolicySettings -TemplateInfo ([pscustomobject]@{ RawJSON = $RawJSON; ReusableSettings = $ReusableSettings }) -Tenant $TenantFilter
                    if ($syncResult.RawJSON) { $RawJSON = $syncResult.RawJSON }
                } else {
                    Write-Verbose 'Catalog: No ReusableSettings provided'
                }

                $Template = $RawJSON | ConvertFrom-Json
                if ($Template.templateReference.templateId) {
                    # Remove settings this tenant does not offer. The comparison paths run the
                    # baseline through the same helper so they diff against what actually lands.
                    $Template = Select-CIPPIntuneAvailableSetting -Policy $Template -TenantFilter $TenantFilter
                    $RawJSON = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
                }

                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $CatalogTemplateId = $Template.templateReference.templateId
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance -NameProperty 'name' -TemplateId $CatalogTemplateId
                if ($FuzzyResult) {
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty Platform, PolicyType, CreationSource
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PUT -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                    $PostType = 'edited'
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'windowsDriverUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsDriverUpdateProfiles'
                $DisplayName = Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJSON -DisplayName $DisplayName
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty inventorySyncStatus, newUpdates, deviceReporting, approvalType
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'windowsFeatureUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsFeatureUpdateProfiles'
                $DisplayName = Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJSON -DisplayName $DisplayName
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty deployableContentDisplayName, endOfSupportDate, installLatestWindows10OnWindows11IneligibleDevice
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy

                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'windowsQualityUpdatePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdatePolicies'
                $DisplayName = Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJSON -DisplayName $DisplayName
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object *
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
            'windowsQualityUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdateProfiles'
                $DisplayName = Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJSON -DisplayName $DisplayName
                $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter
                $FuzzyResult = Find-CIPPFuzzyPolicyMatch -DisplayName $DisplayName -ExistingPolicies $CheckExististing -MaxDistance $LevenshteinDistance
                if ($FuzzyResult) {
                    $PostType = 'edited'
                    $PolicyFile = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty releaseDateDisplayName, deployableContentDisplayName
                    $RawJSON = ConvertTo-Json -InputObject $PolicyFile -Depth 100 -Compress
                    $ExistingID = $FuzzyResult.Policy
                    if ($FuzzyResult.MatchType -eq 'fuzzy') {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Fuzzy matched policy '$($FuzzyResult.OriginalName)' for template '$DisplayName' (distance=$($FuzzyResult.Distance))" -Sev Info
                    }
                    Write-Host 'We are editing'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL/$($ExistingID.Id)" -tenantid $TenantFilter -type PATCH -body $RawJSON
                    $CreateRequest = $FuzzyResult.Policy
                } else {
                    $PostType = 'added'
                    $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $TenantFilter -type POST -body $RawJSON
                    Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Added policy $($DisplayName) via template" -Sev Info
                }
            }
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "$($PostType) policy $($DisplayName)" -Sev Info
        if ($AssignTo) {
            Write-Host "Assigning policy to $($AssignTo) with ID $($CreateRequest.id) and type $TemplateTypeURL for tenant $TenantFilter"
            Write-Host "ID is $($CreateRequest.id)"

            $AssignParams = @{
                GroupName      = $AssignTo
                PolicyId       = $CreateRequest.id
                PlatformType   = $PlatformType
                Type           = $TemplateTypeURL
                TenantFilter   = $tenantFilter
                ExcludeGroup   = $ExcludeGroup
                AssignmentMode = $AssignmentMode
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
