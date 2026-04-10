function Set-CIPPDefenderEDRPolicy {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        $EDR,
        $Headers,
        [string]$APIName,
        [switch]$TemplateOnly
    )

    $EDRSettings = [System.Collections.Generic.List[object]]::new()

    if ($EDR.SampleSharing) {
        $EDRSettings.Add(@{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '6998c81e-2814-4f5e-b492-a6159128a97b' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        value                         = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing_1'
                        settingValueTemplateReference = @{ settingValueTemplateId = 'f72c326c-7c5b-4224-b890-0b9b54522bd9' }
                    }
                }
            })
    }

    if ($EDR.Config) {
        $EDRSettings.Add(@{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '23ab0ea3-1b12-429a-8ed0-7390cf699160' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        value                         = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype_autofromconnector'
                        settingValueTemplateReference = @{ settingValueTemplateId = 'e5c7c98c-c854-4140-836e-bd22db59d651' }
                        children                      = @(
                            @{
                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                settingDefinitionId = 'device_vendor_msft_windowsadvancedthreatprotection_onboarding_fromconnector'
                                simpleSettingValue  = @{
                                    '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSecretSettingValue'
                                    value         = 'Microsoft ATP connector enabled'
                                    valueState    = 'NotEncrypted'
                                }
                            }
                        )
                    }
                }
            })
    }

    if (($EDRSettings | Measure-Object).Count -gt 0) {
        $EDRBodyObj = @{
            name              = 'EDR Configuration'
            description       = ''
            platforms         = 'windows10'
            technologies      = 'mdm,microsoftSense'
            roleScopeTagIds   = @('0')
            templateReference = @{templateId = '0385b795-0f2f-44ac-8602-9f65bf6adede_1' }
            settings          = @($EDRSettings)
        }
        if ($TemplateOnly) { return $EDRBodyObj }
        $EDRbody = ConvertTo-Json -Depth 15 -Compress -InputObject $EDRBodyObj
        Write-Host ($EDRbody)
        $CheckExistingEDR = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter | Where-Object -Property Name -EQ 'EDR Configuration'
        if ($CheckExistingEDR) {
            "$($TenantFilter): EDR Policy already exists. Skipping"
        } else {
            $EDRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter -type POST -body $EDRbody
            if ($EDR.AssignTo -and $EDR.AssignTo -ne 'none') {
                $AssignBody = if ($EDR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($EDR.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($EDRRequest.id)')/assign" -tenantid $TenantFilter -type POST -body $AssignBody
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned EDR policy $($DisplayName) to $($EDR.AssignTo)" -Sev 'Info'
            }
            "$($TenantFilter): Successfully added EDR Settings"
        }
    }
}
