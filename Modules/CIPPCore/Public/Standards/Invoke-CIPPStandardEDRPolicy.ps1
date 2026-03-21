function Invoke-CIPPStandardEDRPolicy {
    <#
	.FUNCTIONALITY
		Internal
    .COMPONENT
		(APIName) EDRPolicy
    .SYNOPSIS
		(Label) Deploy Microsoft Defender EDR Policy
    .DESCRIPTION
		(Helptext) Deploys a Microsoft Defender for Endpoint (EDR) configuration policy via Intune using the Endpoint Detection and Response template. Configures sample sharing and auto-onboarding via the MDE connector.
		(DocsDescription) This standard deploys a Microsoft Defender EDR (Endpoint Detection and Response) configuration policy to Windows 10/11 devices via Intune. It uses the MDE onboarding template (0385b795) with auto-configuration from the MDE connector. Sample sharing is configurable. The policy is assigned based on your selection.
    .NOTES
		CAT
			Device Management Standards
		TAG
		ADDEDCOMPONENT
			{"type":"textField","name":"standards.EDRPolicy.DisplayName","label":"Policy Display Name","defaultValue":"Default EDR Policy"}
			{"type":"autoComplete","multiple":false,"creatable":false,"label":"Sample Sharing","name":"standards.EDRPolicy.SampleSharing","options":[{"label":"None","value":"0"},{"label":"All samples","value":"1"}]}
			{"type":"autoComplete","multiple":false,"creatable":false,"label":"Assign To","name":"standards.EDRPolicy.AssignTo","options":[{"label":"None","value":"none"},{"label":"All Devices","value":"AllDevices"},{"label":"All Users","value":"AllUsers"},{"label":"All Devices and Users","value":"AllDevicesAndUsers"}]}
		IMPACT
			Low Impact
		ADDEDDATE
			2026-03-21
		POWERSHELLEQUIVALENT
			Graph API
		RECOMMENDEDBY
		UPDATECOMMENTBLOCK
			Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
		https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EDRPolicy' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1', 'WIN_DEF_ATP')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $PolicyName = $Settings.DisplayName ?? 'Default EDR Policy'

    $EDRTemplateId = '0385b795-0f2f-44ac-8602-9f65bf6adede_1'

    $SampleSharingValue = $Settings.SampleSharing.value ?? '0'

    $EDRSettings = @(
        @{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing'
                settingInstanceTemplateReference = @{
                    settingInstanceTemplateId = '6998c81e-2814-4f5e-b492-a6159128a97b'
                }
                choiceSettingValue               = @{
                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    value                         = "device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing_$SampleSharingValue"
                    settingValueTemplateReference = @{
                        settingValueTemplateId = 'f72c326c-7c5b-4224-b890-0b9b54522bd9'
                    }
                    children                      = @()
                }
            }
        },

        @{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype'
                settingInstanceTemplateReference = @{
                    settingInstanceTemplateId = '23ab0ea3-1b12-429a-8ed0-7390cf699160'
                }
                choiceSettingValue               = @{
                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    value                         = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype_autofromconnector'
                    settingValueTemplateReference = @{
                        settingValueTemplateId = 'e5c7c98c-c854-4140-836e-bd22db59d651'
                    }
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
        }
    )

    try {
        $ExistingPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant
        $ExistingPolicy = $ExistingPolicies | Where-Object { $_.name -eq $PolicyName }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Failed to retrieve existing policies. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $StateIsCorrect = $null -ne $ExistingPolicy

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Policy '$PolicyName' already exists. Skipping." -sev Info
        } else {
            try {
                $PolBody = ConvertTo-Json -Depth 15 -Compress -InputObject @{
                    name              = $PolicyName
                    description       = 'Deployed by CIPP Standards - Microsoft Defender EDR Policy'
                    platforms         = 'windows10'
                    technologies      = 'mdm,microsoftSense'
                    roleScopeTagIds   = @('0')
                    templateReference = @{
                        templateId = $EDRTemplateId
                    }
                    settings          = @($EDRSettings)
                }

                $PolicyRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant -type POST -body $PolBody -AsApp $true

                # Assignment
                $AssignTo = $Settings.AssignTo.value ?? 'none'
                if ($AssignTo -ne 'none') {
                    $AssignBody = if ($AssignTo -eq 'AllDevicesAndUsers') {
                        '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}'
                    } elseif ($AssignTo -eq 'AllDevices') {
                        '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}}]}'
                    } elseif ($AssignTo -eq 'AllUsers') {
                        '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}'
                    }

                    if ($AssignBody) {
                        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($PolicyRequest.id)')/assign" -tenantid $Tenant -type POST -body $AssignBody -AsApp $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Assigned policy '$PolicyName' to '$AssignTo'." -sev Info
                    }
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Successfully deployed policy '$PolicyName'." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Failed to deploy EDR policy. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Policy '$PolicyName' exists and is configured." -sev Info
        } else {
            Write-StandardsAlert -message "EDRPolicy: Policy '$PolicyName' does not exist." -object $ExistingPolicy -tenant $Tenant -standardName 'EDRPolicy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "EDRPolicy: Policy '$PolicyName' does not exist." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            PolicyExists = $StateIsCorrect
            PolicyName   = $PolicyName
        }
        $ExpectedValue = [PSCustomObject]@{
            PolicyExists = $true
            PolicyName   = $PolicyName
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.EDRPolicy' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EDRPolicy' -FieldValue ([bool]$StateIsCorrect) -StoreAs bool -Tenant $Tenant
    }
}
