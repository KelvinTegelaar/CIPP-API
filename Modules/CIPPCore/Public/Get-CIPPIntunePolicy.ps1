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

    # Custom (OMA-URI) device configurations read back from Graph with their secret values encrypted
    # (value 'PGEvPg==', isEncrypted, secretReferenceValueId), whereas the template captured by
    # New-CIPPIntuneTemplate stores them decrypted. Without decrypting the read-back copy the drift
    # compare can never converge and the template re-deploys on every standards run. Decrypt here the
    # same way capture and the DB cache already do, but never let a decrypt failure sink the whole
    # policy read - fall back to the undecrypted object so the rest of the policy still returns.
    function Get-CIPPIntunePolicyOmaDecryptedValue {
        param($DeviceConfiguration, $DeviceConfigurationId, $TenantFilter)
        if (@($DeviceConfiguration.omaSettings | Where-Object { $_.secretReferenceValueId }).Count -gt 0) {
            try {
                $DeviceConfiguration = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration $DeviceConfiguration -DeviceConfigurationId $DeviceConfigurationId -TenantFilter $TenantFilter
            } catch {
                Write-Information "Failed to decrypt OMA settings for device configuration '$($DeviceConfiguration.displayName)': $($_.Exception.Message)"
            }
        }
        return $DeviceConfiguration
    }

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

                # Reading a concrete collection makes Graph omit @odata.type from every item, but
                # callers need the concrete type to address the policy - its assignments live under
                # that collection. The collection a policy came from is the authoritative answer, so
                # record it here rather than leaving each caller to infer it from the payload.
                foreach ($Policy in $androidPolicies) {
                    $null = $Policy | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.androidManagedAppProtection' -Force
                }
                foreach ($Policy in $iOSPolicies) {
                    $null = $Policy | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value '#microsoft.graph.iosManagedAppProtection' -Force
                }

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
                        # The definition must be expanded: without it every bind is built on an empty id
                        # and the compare against a template can never match.
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues?`$expand=definition" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force
                        $inputvar = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $policy.id -TenantFilter $tenantFilter -DefinitionValues $definitionValues
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')/definitionValues?`$expand=definition" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force
                        $inputvar = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $PolicyId -TenantFilter $tenantFilter -DefinitionValues $definitionValues
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        # The definition must be expanded: without it every bind is built on an empty id
                        # and the compare against a template can never match.
                        $definitionValues = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/definitionValues?`$expand=definition" -tenantid $tenantFilter
                        $policy | Add-Member -MemberType NoteProperty -Name 'definitionValues' -Value $definitionValues -Force
                        $inputvar = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $policy.id -TenantFilter $tenantFilter -DefinitionValues $definitionValues
                        $policyJson = ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policies
                }
            }
            'AppConfiguration' {
                # Managed-device app configuration policies. Without this case the IntuneTemplate
                # standard could never find a deployed app configuration and reported it missing on
                # every run while remediation kept patching the policy that was already there.
                $PlatformType = 'deviceAppManagement'
                $TemplateTypeURL = 'mobileAppConfigurations'
                $ExcludedProperties = @('id', 'createdDateTime', 'lastModifiedDateTime', 'version', '@odata.context')

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty $ExcludedProperties
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $policyDetails = $policy | Select-Object * -ExcludeProperty $ExcludedProperties
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty $ExcludedProperties
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
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
                        # Capture the id before Select-Object strips it - the decrypt helper needs it to
                        # resolve each OMA secret.
                        $DeviceConfigurationId = $policy.id
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyDetails = Get-CIPPIntunePolicyOmaDecryptedValue -DeviceConfiguration $policyDetails -DeviceConfigurationId $DeviceConfigurationId -TenantFilter $tenantFilter
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        # Capture the id before Select-Object strips it - the decrypt helper needs it to
                        # resolve each OMA secret.
                        $DeviceConfigurationId = $policy.id
                        $policyDetails = $policy | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyDetails = Get-CIPPIntunePolicyOmaDecryptedValue -DeviceConfiguration $policyDetails -DeviceConfigurationId $DeviceConfigurationId -TenantFilter $tenantFilter
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        # Capture the id before Select-Object strips it - the decrypt helper needs it to
                        # resolve each OMA secret.
                        $DeviceConfigurationId = $policy.id
                        $policyDetails = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')" -tenantid $tenantFilter
                        $policyDetails = $policyDetails | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
                        $policyDetails = Get-CIPPIntunePolicyOmaDecryptedValue -DeviceConfiguration $policyDetails -DeviceConfigurationId $DeviceConfigurationId -TenantFilter $tenantFilter
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
            'hardwareConfigurations' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'hardwareConfigurations'

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
            'Intents' {
                $PlatformType = 'deviceManagement'
                $TemplateTypeURL = 'intents'

                if ($DisplayName) {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    $policy = $policies | Where-Object -Property displayName -EQ $DisplayName | Sort-Object -Property lastModifiedDateTime -Descending | Select-Object -First 1
                    if ($policy) {
                        $settings = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/settings" -tenantid $tenantFilter
                        $policyDetails = [PSCustomObject]@{
                            displayName = $policy.displayName
                            description = $policy.description
                            templateId  = $policy.templateId
                            settings    = @($settings)
                        }
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } elseif ($PolicyId) {
                    $policy = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')" -tenantid $tenantFilter
                    if ($policy) {
                        $settings = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$PolicyId')/settings" -tenantid $tenantFilter
                        $policyDetails = [PSCustomObject]@{
                            displayName = $policy.displayName
                            description = $policy.description
                            templateId  = $policy.templateId
                            settings    = @($settings)
                        }
                        $policyJson = ConvertTo-Json -InputObject $policyDetails -Depth 100 -Compress
                        $policy | Add-Member -MemberType NoteProperty -Name 'cippconfiguration' -Value $policyJson -Force
                    }
                    return $policy
                } else {
                    $policies = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL" -tenantid $tenantFilter
                    foreach ($policy in $policies) {
                        $settings = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/$PlatformType/$TemplateTypeURL('$($policy.id)')/settings" -tenantid $tenantFilter
                        $policyDetails = [PSCustomObject]@{
                            displayName = $policy.displayName
                            description = $policy.description
                            templateId  = $policy.templateId
                            settings    = @($settings)
                        }
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
