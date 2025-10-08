function Invoke-AddDefenderDeployment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Tenants = ($Request.Body.selectedTenants).value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants -IncludeErrors).defaultDomainName }
    $Compliance = $Request.Body.Compliance
    $PolicySettings = $Request.Body.Policy
    $DefenderExclusions = $Request.Body.Exclusion
    $ASR = $Request.Body.ASR
    $EDR = $Request.Body.EDR
    $Results = foreach ($tenant in $Tenants) {
        try {
            if ($Compliance) {
                $SettingsObject = @{
                    id                                                  = 'fc780465-2017-40d4-a0c5-307022471b92'
                    androidEnabled                                      = [bool]$Compliance.ConnectAndroid
                    iosEnabled                                          = [bool]$Compliance.ConnectIos
                    windowsEnabled                                      = [bool]$Compliance.Connectwindows
                    macEnabled                                          = [bool]$Compliance.ConnectMac
                    partnerUnsupportedOsVersionBlocked                  = [bool]$Compliance.BlockunsupportedOS
                    partnerUnresponsivenessThresholdInDays              = 7
                    allowPartnerToCollectIOSApplicationMetadata         = [bool]$Compliance.ConnectIosCompliance
                    allowPartnerToCollectIOSPersonalApplicationMetadata = [bool]$Compliance.ConnectIosCompliance
                    androidMobileApplicationManagementEnabled           = [bool]$Compliance.ConnectAndroidCompliance
                    iosMobileApplicationManagementEnabled               = [bool]$Compliance.appSync
                    microsoftDefenderForEndpointAttachEnabled           = [bool]$true
                }
                $SettingsObj = $SettingsObject | ConvertTo-Json -Compress
                try {
                    $ExistingSettings = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92' -tenantid $tenant

                    # Check if any setting doesn't match
                    foreach ($key in $SettingsObject.Keys) {
                        if ($ExistingSettings.$key -ne $SettingsObject[$key]) {
                            $ExistingSettings = $false
                            break
                        }
                    }
                } catch {
                    $ExistingSettings = $false
                }
                if ($ExistingSettings) {
                    "Defender Intune Configuration already correct and active for $($tenant). Skipping"
                } else {
                    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $tenant -type POST -body $SettingsObj -AsApp $true
                    "$($tenant): Successfully set Defender Compliance and Reporting settings. Please remember to enable the Intune Connector in the Defender portal."
                }
            }


            if ($PolicySettings) {
                $Settings = switch ($PolicySettings) {
                    { $_.ScanArchives } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowarchivescanning'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_allowarchivescanning_1'; settingValueTemplateReference = @{settingValueTemplateId = '9ead75d4-6f30-4bc5-8cc5-ab0f999d79f0' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = '7c5c9cde-f74d-4d11-904f-de4c27f72d89' } } }
                    } { $_.AllowBehavior } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowbehaviormonitoring' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_allowbehaviormonitoring_1'; settingValueTemplateReference = @{settingValueTemplateId = '905921da-95e2-4a10-9e30-fe5540002ce1' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = '8eef615a-1aa0-46f4-a25a-12cbe65de5ab' } } }
                    } { $_.AllowCloudProtection } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowcloudprotection'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowcloudprotection_1'; settingValueTemplateReference = @{settingValueTemplateId = '16fe8afd-67be-4c50-8619-d535451a500c' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = '7da139f1-9b7e-407d-853a-c2e5037cdc70' } } }
                    } { $_.AllowEmailScanning } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowemailscanning' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowemailscanning_1'; settingValueTemplateReference = @{settingValueTemplateId = 'fdf107fd-e13b-4507-9d8f-db4d93476af9' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'b0d9ee81-de6a-4750-86d7-9397961c9852' } } }
                    } { $_.AllowFullScanNetwork } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowfullscanonmappednetworkdrives' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowfullscanonmappednetworkdrives_1' ; settingValueTemplateReference = @{settingValueTemplateId = '3e920b10-3773-4ac5-957e-e5573aec6d04' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'dac47505-f072-48d6-9f23-8d93262d58ed' } } }
                    } { $_.AllowFullScanRemovable } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowfullscanremovabledrivescanning' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_allowfullscanremovabledrivescanning_1' ; settingValueTemplateReference = @{settingValueTemplateId = '366c5727-629b-4a81-b50b-52f90282fa2c' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'fb36e70b-5bc9-488a-a949-8ea3ac1634d5' } } }
                    } { $_.AllowDownloadable } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowioavprotection' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowioavprotection_1'; settingValueTemplateReference = @{settingValueTemplateId = 'df4e6cbd-f7ff-41c8-88cd-fa25264a237e' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'fa06231d-aed4-4601-b631-3a37e85b62a0' } } }
                    } { $_.AllowRealTime } {
                        @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring_1'; settingValueTemplateReference = @{settingValueTemplateId = '0492c452-1069-4b91-9363-93b8e006ab12' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f0790e28-9231-4d37-8f44-84bb47ca1b3e' } } }
                    } { $_.AllowNetwork } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowscanningnetworkfiles' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_allowscanningnetworkfiles_1' ; settingValueTemplateReference = @{settingValueTemplateId = '7b8c858c-a17d-4623-9e20-f34b851670ce' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f8f28442-0a6b-4b52-b42c-d31d9687c1cf' } } }
                    } { $_.AllowScriptScan } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowscriptscanning'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowscriptscanning_1'; settingValueTemplateReference = @{settingValueTemplateId = 'ab9e4320-c953-4067-ac9a-be2becd06b4a' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = '000cf176-949c-4c08-a5d4-90ed43718db7' } } }
                    } { $_.AllowUI } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowuseruiaccess' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowuseruiaccess_1' ; settingValueTemplateReference = @{settingValueTemplateId = '4b6c9739-4449-4006-8e5f-3049136470ea' } }; settingInstanceTemplateReference = @{settingInstanceTemplateId = '0170a900-b0bc-4ccc-b7ce-dda9be49189b' } } }
                    } { $_.CheckSigs } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_checkforsignaturesbeforerunningscan' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_checkforsignaturesbeforerunningscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = '010779d1-edd4-441d-8034-89ad57a863fe' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = '4fea56e3-7bb6-4ad3-88c6-e364dd2f97b9' } } }
                    } { $_.DisableCatchupFullScan } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_disablecatchupfullscan'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_disablecatchupfullscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = '1b26092f-48c4-447b-99d4-e9c501542f1c' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f881b08c-f047-40d2-b7d9-3dde7ce9ef64' } } }
                    } { $_.DisableCatchupQuickScan } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_disablecatchupquickscan' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_disablecatchupquickscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = 'd263ced7-0d23-4095-9326-99c8b3f5d35b' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'dabf6781-9d5d-42da-822a-d4327aa2bdd1' } } }
                    } { $_.EnableNetworkProtection } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_enablenetworkprotection' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_enablenetworkprotection_$($_.EnableNetworkProtection.value)" ; settingValueTemplateReference = @{settingValueTemplateId = 'ee58fb51-9ae5-408b-9406-b92b643f388a' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f53ab20e-8af6-48f5-9fa1-46863e1e517e' } } }
                    } { $_.LowCPU } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_enablelowcpupriority' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_enablelowcpupriority_1' ; settingValueTemplateReference = @{settingValueTemplateId = '045a4a13-deee-4e24-9fe4-985c9357680d' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'cdeb96cf-18f5-4477-a710-0ea9ecc618af' } } }
                    } { $_.CloudBlockLevel } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_cloudblocklevel'; settingInstanceTemplateReference = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = 'c7a37009-c16e-4145-84c8-89a8c121fb15' }; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_cloudblocklevel_$($_.CloudBlockLevel.value ?? '0')"; settingValueTemplateReference = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '517b4e84-e933-42b9-b92f-00e640b1a82d' } } } }
                    } { $_.AvgCPULoadFactor } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_avgcpuloadfactor' ; settingInstanceTemplateReference = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference' ; settingInstanceTemplateId = '816cc03e-8f96-4cba-b14f-2658d031a79a' } ; simpleSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'; value = ($_.AvgCPULoadFactor ?? 50); settingValueTemplateReference = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '37195fb1-3743-4c8e-a0ce-b6fae6fa3acd' } } } }
                    } { $_.CloudExtendedTimeout } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_cloudextendedtimeout'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = 'f61c2788-14e4-4e80-a5a7-bf2ff5052f63' }; simpleSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'; value = ($_.CloudExtendedTimeout ?? 50); settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '608f1561-b603-46bd-bf5f-0b9872002f75' } } } }
                    } { $_.SignatureUpdateInterval } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_signatureupdateinterval'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = '89879f27-6b7d-44d4-a08e-0a0de3e9663d' }; simpleSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'; value = ($_.SignatureUpdateInterval ?? 8); settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '0af6bbed-a74a-4d08-8587-b16b10b774cb' } } } }
                    } { $_.MeteredConnectionUpdates } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_defender_configuration_meteredconnectionupdates'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = '7e3aaffb-309f-46de-8cd7-25c1a3b19e5b' }; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_defender_configuration_meteredconnectionupdates_1'; settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '20cf972c-be3f-4bc1-93d3-781829d55233' } } } }
                    } { $_.AllowOnAccessProtection } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowonaccessprotection'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = 'afbc322b-083c-4281-8242-ebbb91398b41' }; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_allowonaccessprotection_$($_.AllowOnAccessProtection.value ?? '1')"; settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = 'ed077fee-9803-44f3-b045-aab34d8e6d52' } } } }
                    } { $_.DisableLocalAdminMerge } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_defender_configuration_disablelocaladminmerge'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = '5f9a9c65-dea7-4987-a5f5-b28cfd9762ba' }; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_defender_configuration_disablelocaladminmerge_1'; settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '3a9774b2-3143-47eb-bbca-d73c0ace2b7e' } } } }
                    } { $_.SubmitSamplesConsent } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_submitsamplesconsent'; settingInstanceTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = 'bc47ce7d-a251-4cae-a8a2-6e8384904ab7' }; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_submitsamplesconsent_$($_.SubmitSamplesConsent.value ?? '2')"; settingValueTemplateReference = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'; settingValueTemplateId = '826ed4b6-e04f-4975-9d23-6f0904b0d87e' } } } }
                    } { $_.Remediation } {
                        @{
                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_threatseveritydefaultaction'; settingInstanceTemplateReference = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'; settingInstanceTemplateId = 'f6394bc5-6486-4728-b510-555f5c161f2b' }
                                groupSettingCollectionValue = @(@{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationGroupSettingValue'
                                        children                                = @(
                                            if ($_.Remediation.Low) { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_threatseveritydefaultaction_lowseveritythreats'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_threatseveritydefaultaction_lowseveritythreats_$($_.Remediation.Low.value)" } } }
                                            if ($_.Remediation.Moderate) { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_threatseveritydefaultaction_moderateseveritythreats'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_threatseveritydefaultaction_moderateseveritythreats_$($_.Remediation.Moderate.value)" } } }
                                            if ($_.Remediation.High) { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_threatseveritydefaultaction_highseveritythreats'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_threatseveritydefaultaction_highseveritythreats_$($_.Remediation.High.value)" } } }
                                            if ($_.Remediation.Severe) { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_threatseveritydefaultaction_severethreats'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_threatseveritydefaultaction_severethreats_$($_.Remediation.Severe.value)" } } }
                                        )
                                    }
                                )
                            }
                        }
                    }

                }
                $CheckExisting = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant
                Write-Host ($CheckExisting | ConvertTo-Json)
                if ('Default AV Policy' -in $CheckExisting.Name) {
                    "$($tenant): AV Policy already exists. Skipping"
                } else {
                    $PolBody = ConvertTo-Json -Depth 10 -Compress -InputObject @{
                        name              = 'Default AV Policy'
                        description       = ''
                        platforms         = 'windows10'
                        technologies      = 'mdm,microsoftSense'
                        roleScopeTagIds   = @('0')
                        templateReference = @{templateId = '804339ad-1553-4478-a742-138fb5807418_1' }
                        settings          = @($Settings)
                    }

                    Write-Information ($PolBody)

                    $PolicyRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $PolBody
                    if ($PolicySettings.AssignTo -ne 'None') {
                        $AssignBody = if ($PolicySettings.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($PolicySettings.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($PolicyRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                        Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenant) -message "Assigned policy $($DisplayName) to $($PolicySettings.AssignTo)" -Sev 'Info'
                    }
                    "$($tenant): Successfully set Default AV Policy settings"
                }
            }
            if ($ASR) {
                # Fallback to block mode
                $Mode = $ASR.Mode ?? 'block'
                $ASRSettings = switch ($ASR) {
                    { $_.BlockObfuscatedScripts } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutionofpotentiallyobfuscatedscripts' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutionofpotentiallyobfuscatedscripts_$Mode" } } }
                    { $_.BlockAdobeChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses_$Mode" } } }
                    { $_.BlockWin32Macro } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros_$Mode" } } }
                    { $_.BlockCredentialStealing } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem_$Mode" } } }
                    { $_.BlockPSExec } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands_$Mode" } } }
                    { $_.WMIPersistence } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription_$Mode" } } }
                    { $_.BlockOfficeExes } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent_$Mode" } } }
                    { $_.BlockOfficeApps } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses_$Mode" } } }
                    { $_.BlockYoungExe } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion_$Mode" } } }
                    { $_.blockJSVB } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent_$Mode" } } }
                    { $_.BlockWebshellForServers } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwebshellcreationforservers' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwebshellcreationforservers_$Mode" } } }
                    { $_.blockOfficeComChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses_$Mode" } } }
                    { $_.BlockSystemTools } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuseofcopiedorimpersonatedsystemtools' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuseofcopiedorimpersonatedsystemtools_$Mode" } } }
                    { $_.blockOfficeChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses_$Mode" } } }
                    { $_.BlockUntrustedUSB } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb_$Mode" } } }
                    { $_.EnableRansomwareVac } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_useadvancedprotectionagainstransomware'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_useadvancedprotectionagainstransomware_$Mode" } } }
                    { $_.BlockExesMail } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail_$Mode" } } }
                    { $_.BlockUnsignedDrivers } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers_$Mode" } } }
                    { $_.BlockSafeMode } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockrebootingmachineinsafemode'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; value = "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockrebootingmachineinsafemode_$Mode" } } }

                }
                $ASRbody = ConvertTo-Json -Depth 15 -Compress -InputObject @{
                    name              = 'ASR Default rules'
                    description       = ''
                    platforms         = 'windows10'
                    technologies      = 'mdm,microsoftSense'
                    roleScopeTagIds   = @('0')
                    templateReference = @{templateId = 'e8c053d6-9f95-42b1-a7f1-ebfd71c67a4b_1' }
                    settings          = @(@{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            settingInstance = @{
                                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                                settingDefinitionId              = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
                                groupSettingCollectionValue      = @(@{children = $ASRSettings })
                                settingInstanceTemplateReference = @{settingInstanceTemplateId = '19600663-e264-4c02-8f55-f2983216d6d7' }
                            }
                        })
                }
                $CheckExististingASR = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant
                if ('ASR Default rules' -in $CheckExististingASR.Name) {
                    "$($tenant): ASR Policy already exists. Skipping"
                } else {
                    Write-Host $ASRbody
                    if (($ASRSettings | Measure-Object).Count -gt 0) {
                        $ASRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $ASRbody
                        Write-Host ($ASRRequest.id)
                        if ($ASR.AssignTo -and $ASR.AssignTo -ne 'none') {
                            $AssignBody = if ($ASR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($asr.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ASRRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                            Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenant) -message "Assigned policy $($DisplayName) to $($ASR.AssignTo)" -Sev 'Info'
                        }
                        "$($tenant): Successfully added ASR Settings"
                    }
                }
            }
            if ($EDR) {
                $EDRSettings = switch ($EDR) {
                    { $_.SampleSharing } {
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            settingInstance = @{
                                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing'
                                choiceSettingValue               = @{
                                    settingValueTemplateReference = @{settingValueTemplateId = 'f72c326c-7c5b-4224-b890-0b9b54522bd9' }
                                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    'value'                       = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing_1'
                                }
                                settingInstanceTemplateReference = @{settingInstanceTemplateId = '6998c81e-2814-4f5e-b492-a6159128a97b' }
                            }
                        }
                    }
                    { $_.Telemetry } {
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            settingInstance = @{
                                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_telemetryreportingfrequency'
                                choiceSettingValue               = @{
                                    settingValueTemplateReference = @{settingValueTemplateId = '350b0bea-b67b-43d4-9a04-c796edb961fd' }
                                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    'value'                       = 'device_vendor_msft_windowsadvancedthreatprotection_configuration_telemetryreportingfrequency_2'
                                }
                                settingInstanceTemplateReference = @{settingInstanceTemplateId = '03de6095-07c4-4f35-be38-c1cd3bae4484' }
                            }
                        }

                    }
                    { $_.Config } {
                        @{
                            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                            settingInstance = @{
                                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                settingDefinitionId              = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype'
                                choiceSettingValue               = @{
                                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                                    'value'                       = 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype_autofromconnector'
                                    settingValueTemplateReference = @{settingValueTemplateId = 'e5c7c98c-c854-4140-836e-bd22db59d651' }
                                    children                      = @(@{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance' ; settingDefinitionId = 'device_vendor_msft_windowsadvancedthreatprotection_onboarding_fromconnector' ; simpleSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationSecretSettingValue' ; value = 'Microsoft ATP connector enabled'; valueState = 'NotEncrypted' } } )
                                }

                                settingInstanceTemplateReference = @{settingInstanceTemplateId = '23ab0ea3-1b12-429a-8ed0-7390cf699160' }
                            }
                        }

                    }
                }
                if (($EDRSettings | Measure-Object).Count -gt 0) {
                    $EDRbody = ConvertTo-Json -Depth 15 -Compress -InputObject @{
                        name              = 'EDR Configuration'
                        description       = ''
                        platforms         = 'windows10'
                        technologies      = 'mdm,microsoftSense'
                        roleScopeTagIds   = @('0')
                        templateReference = @{templateId = '0385b795-0f2f-44ac-8602-9f65bf6adede_1' }
                        settings          = @($EDRSettings)
                    }
                    Write-Host ( $EDRbody)
                    $CheckExististingEDR = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant | Where-Object -Property Name -EQ 'EDR Configuration'
                    if ('EDR Configuration' -in $CheckExististingEDR.Name) {
                        "$($tenant): EDR Policy already exists. Skipping"
                    } else {
                        $EDRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $EDRbody
                        if ($ASR -and $ASR.AssignTo -ne 'none') {
                            $AssignBody = if ($ASR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($asr.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($EDRRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                            Write-LogMessage -headers $Headers -API $APINAME -tenant $($tenant) -message "Assigned EDR policy $($DisplayName) to $($ASR.AssignTo)" -Sev 'Info'
                        }
                        "$($tenant): Successfully added EDR Settings"
                    }
                }
            }
            # Exclusion Policy Section
            if ($DefenderExclusions) {
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
                    $ExclusionBody = ConvertTo-Json -Depth 15 -Compress -InputObject @{
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
                    $CheckExistingExclusion = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant
                    if ('Default AV Exclusion Policy' -in $CheckExistingExclusion.Name) {
                        "$($tenant): Exclusion Policy already exists. Skipping"
                    } else {
                        $ExclusionRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $ExclusionBody
                        if ($ExclusionAssignTo -and $ExclusionAssignTo -ne 'none') {
                            $AssignBody = if ($ExclusionAssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($ExclusionAssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExclusionRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Assigned Exclusion policy to $($ExclusionAssignTo)" -Sev 'Info'
                        }
                        "$($tenant): Successfully set Default AV Exclusion Policy settings"
                    }
                }
            }
        } catch {
            "Failed to add policy for $($tenant): $($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Failed adding policy $($DisplayName). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = @($Results) }
        })

}
