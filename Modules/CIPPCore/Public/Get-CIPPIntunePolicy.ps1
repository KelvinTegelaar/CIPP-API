function Get-CIPPIntunePolicy {
    param (
        [Parameter(Mandatory = $true)]
        $TemplateType,
        $DisplayName,
        $PolicyId,
        $Headers,
        $APINAME,
        $tenantFilter
    )

    try {
        switch ($TemplateType) {
            'AppProtection' {
                $PlatformType = 'deviceAppManagement'
                $AndroidTemplateTypeURL = 'androidManagedAppProtections'
                $iOSTemplateTypeURL = 'iosManagedAppProtections'

                # Define bulk request for both platforms - used by all scenarios
                $BulkRequests = @(
                    @{
                        id     = 'AndroidPolicies'
                        url    = "$PlatformType/$AndroidTemplateTypeURL"
                        method = 'GET'
                    },
                    @{
                        id     = 'iOSPolicies'
                        url    = "$PlatformType/$iOSTemplateTypeURL"
                        method = 'GET'
                    }
                )
                $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $tenantFilter

                $androidPolicies = ($BulkResults | Where-Object { $_.id -eq 'AndroidPolicies' }).body.value
                $iOSPolicies = ($BulkResults | Where-Object { $_.id -eq 'iOSPolicies' }).body.value

                if ($DisplayName) {
                    $androidPolicy = $androidPolicies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    $iOSPolicy = $iOSPolicies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1

                    # Return the matching policy (Android or iOS) - using full data from bulk request
                    if ($androidPolicy) {
                        $policyJson = ConvertTo-Json -InputObject $androidPolicy -Depth 100 -Compress
                        $androidPolicy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                        return $androidPolicy
                    } elseif ($iOSPolicy) {
                        $policyJson = ConvertTo-Json -InputObject $iOSPolicy -Depth 100 -Compress
                        $iOSPolicy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                        return $iOSPolicy
                    }
                    return $null

                } elseif ($PolicyId) {
                    $androidPolicy = $androidPolicies | Where-Object -Property id -EQ $PolicyId
                    $iOSPolicy = $iOSPolicies | Where-Object -Property id -EQ $PolicyId

                    # Return the matching policy - using full data from bulk request
                    if ($androidPolicy) {
                        $policyJson = ConvertTo-Json -InputObject $androidPolicy -Depth 100 -Compress
                        $androidPolicy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                        return $androidPolicy
                    } elseif ($iOSPolicy) {
                        $policyJson = ConvertTo-Json -InputObject $iOSPolicy -Depth 100 -Compress
                        $iOSPolicy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                        return $iOSPolicy
                    }
                    return $null

                } else {
                    # Process all Android policies
                    foreach ($policy in $androidPolicies) {
                        $policyJson = ConvertTo-Json -InputObject $policy -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }

                    # Process all iOS policies
                    foreach ($policy in $iOSPolicies) {
                        $policyJson = ConvertTo-Json -InputObject $policy -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }

                    # Combine and return all policies
                    $allPolicies = [System.Collections.Generic.List[object]]::new()
                    if ($androidPolicies) { $allPolicies.AddRange($androidPolicies) }
                    if ($iOSPolicies) { $allPolicies.AddRange($iOSPolicies) }
                    return $allPolicies
                }
            }
            'deviceCompliancePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceCompliancePolicies'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)" -tenantid $tenantFilter
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)" -tenantid $tenantFilter
                    if ($policy) {
                        $policyJson = ConvertTo-Json -InputObject $policy -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)" -tenantid $tenantFilter
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'Admin' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'groupPolicyConfigurations'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force

                        $templateJsonItems = $definitionValues
                        $templateJsonSource = foreach ($templateJsonItem in $templateJsonItems) {
                            $presentationValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues('$($templateJsonItem.id)')/presentationValues?`$expand=presentation" -tenantid $tenantFilter | ForEach-Object {
                                $obj = $_
                                if ($obj.id) {
                                    $presObj = @{
                                        id                        = $obj.id
                                        'presentation@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')/presentations('$($obj.presentation.id)')"
                                    }
                                    if ($obj.values) { $presObj['values'] = $obj.values }
                                    if ($obj.value) { $presObj['value'] = $obj.value }
                                    if ($obj.'@odata.type') { $presObj['@odata.type'] = $obj.'@odata.type' }
                                    [pscustomobject]$presObj
                                }
                            }
                            [PSCustomObject]@{
                                'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')"
                                enabled                 = $templateJsonItem.enabled
                                presentationValues      = @($presentationValues)
                            }
                        }
                        $inputvar = [pscustomobject]@{
                            added      = @($templateJsonSource)
                            updated    = @()
                            deletedIds = @()
                        }
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')/definitionValues" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force

                        $templateJsonItems = $definitionValues
                        $templateJsonSource = foreach ($templateJsonItem in $templateJsonItems) {
                            $presentationValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')/definitionValues('$($templateJsonItem.id)')/presentationValues?`$expand=presentation" -tenantid $tenantFilter | ForEach-Object {
                                $obj = $_
                                if ($obj.id) {
                                    $presObj = @{
                                        id                        = $obj.id
                                        'presentation@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')/presentations('$($obj.presentation.id)')"
                                    }
                                    if ($obj.values) { $presObj['values'] = $obj.values }
                                    if ($obj.value) { $presObj['value'] = $obj.value }
                                    if ($obj.'@odata.type') { $presObj['@odata.type'] = $obj.'@odata.type' }
                                    [pscustomobject]$presObj
                                }
                            }
                            [PSCustomObject]@{
                                'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')"
                                enabled                 = $templateJsonItem.enabled
                                presentationValues      = @($presentationValues)
                            }
                        }
                        $inputvar = [pscustomobject]@{
                            added      = @($templateJsonSource)
                            updated    = @()
                            deletedIds = @()
                        }
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force

                        $templateJsonItems = $definitionValues
                        $templateJsonSource = foreach ($templateJsonItem in $templateJsonItems) {
                            $presentationValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues('$($templateJsonItem.id)')/presentationValues?`$expand=presentation" -tenantid $tenantFilter | ForEach-Object {
                                $obj = $_
                                if ($obj.id) {
                                    $presObj = @{
                                        id                        = $obj.id
                                        'presentation@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')/presentations('$($obj.presentation.id)')"
                                    }
                                    if ($obj.values) { $presObj['values'] = $obj.values }
                                    if ($obj.value) { $presObj['value'] = $obj.value }
                                    if ($obj.'@odata.type') { $presObj['@odata.type'] = $obj.'@odata.type' }
                                    [pscustomobject]$presObj
                                }
                            }
                            [PSCustomObject]@{
                                'definition@odata.bind' = "https://graph.microsoft.com/beta/deviceManagement/groupPolicyDefinitions('$($templateJsonItem.definition.id)')"
                                enabled                 = $templateJsonItem.enabled
                                presentationValues      = @($presentationValues)
                            }
                        }
                        $inputvar = [pscustomobject]@{
                            added      = @($templateJsonSource)
                            updated    = @()
                            deletedIds = @()
                        }
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'Device' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'deviceConfigurations'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'Catalog' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'configurationPolicies'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property Name -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')?`$expand=settings" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object name, description, settings, platforms, technologies, templateReference
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')?`$expand=settings" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object name, description, settings, platforms, technologies, templateReference
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')?`$expand=settings" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object name, description, settings, platforms, technologies, templateReference
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'windowsDriverUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsDriverUpdateProfiles'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'windowsFeatureUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsFeatureUpdateProfiles'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'windowsQualityUpdatePolicies' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdatePolicies'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'windowsQualityUpdateProfiles' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'windowsQualityUpdateProfiles'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            default {
                return $null
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenantFilter) -message "Failed to get policy. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to get policy for $($tenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
