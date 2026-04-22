function Set-CIPPDefenderExclusionPolicy {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        $DefenderExclusions,
        $Headers,
        [string]$APIName,
        [switch]$TemplateOnly
    )

    $ExclusionAssignTo = $DefenderExclusions.AssignTo
    if ($DefenderExclusions.excludedExtensions) {
        $ExcludedExtensions = $DefenderExclusions.excludedExtensions | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
            @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'; value = $_ }
        }
    }
    if ($DefenderExclusions.excludedPaths) {
        $ExcludedPaths = $DefenderExclusions.excludedPaths | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
            @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'; value = $_ }
        }
    }
    if ($DefenderExclusions.excludedProcesses) {
        $ExcludedProcesses = $DefenderExclusions.excludedProcesses | Where-Object { $_ -and $_.Trim() } | ForEach-Object {
            @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'; value = $_ }
        }
    }

    $ExclusionSettings = [System.Collections.Generic.List[System.Object]]::new()
    if ($ExcludedExtensions.Count -gt 0) {
        $ExclusionSettings.Add(@{
                id              = '2'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                    settingDefinitionId              = 'device_vendor_msft_policy_config_defender_excludedextensions'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'c203725b-17dc-427b-9470-673a2ce9cd5e' }
                    simpleSettingCollectionValue     = @($ExcludedExtensions)
                }
            })
    }
    if ($ExcludedPaths.Count -gt 0) {
        $ExclusionSettings.Add(@{
                id              = '1'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                    settingDefinitionId              = 'device_vendor_msft_policy_config_defender_excludedpaths'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'aaf04adc-c639-464f-b4a7-152e784092e8' }
                    simpleSettingCollectionValue     = @($ExcludedPaths)
                }
            })
    }
    if ($ExcludedProcesses.Count -gt 0) {
        $ExclusionSettings.Add(@{
                id              = '0'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                    settingDefinitionId              = 'device_vendor_msft_policy_config_defender_excludedprocesses'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '96b046ed-f138-4250-9ae0-b0772a93d16f' }
                    simpleSettingCollectionValue     = @($ExcludedProcesses)
                }
            })
    }

    if ($ExclusionSettings.Count -gt 0) {
        $ExclusionBodyObj = @{
            name              = 'Default AV Exclusion Policy'
            displayName       = 'Default AV Exclusion Policy'
            settings          = @($ExclusionSettings)
            platforms         = 'windows10'
            technologies      = 'mdm,microsoftSense'
            templateReference = @{
                templateId             = '45fea5e9-280d-4da1-9792-fb5736da0ca9_1'
                templateFamily         = 'endpointSecurityAntivirus'
                templateDisplayName    = 'Microsoft Defender Antivirus exclusions'
                templateDisplayVersion = 'Version 1'
            }
        }
        if ($TemplateOnly) { return $ExclusionBodyObj }
        $ExclusionBody = ConvertTo-Json -Depth 15 -Compress -InputObject $ExclusionBodyObj
        $CheckExistingExclusion = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter
        if ('Default AV Exclusion Policy' -in $CheckExistingExclusion.Name) {
            "$($TenantFilter): Exclusion Policy already exists. Skipping"
        } else {
            $ExclusionRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter -type POST -body $ExclusionBody
            if ($ExclusionAssignTo -and $ExclusionAssignTo -ne 'none') {
                $AssignBody = if ($ExclusionAssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($ExclusionAssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExclusionRequest.id)')/assign" -tenantid $TenantFilter -type POST -body $AssignBody
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned Exclusion policy to $($ExclusionAssignTo)" -Sev 'Info'
            }
            "$($TenantFilter): Successfully set Default AV Exclusion Policy settings"
        }
    }
}
