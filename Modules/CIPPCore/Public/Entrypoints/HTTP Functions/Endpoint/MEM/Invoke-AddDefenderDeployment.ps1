using namespace System.Net

Function Invoke-AddDefenderDeployment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenants = ($Request.body.selectedTenants).value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants -IncludeErrors).defaultDomainName }
    $Compliance = $request.body.Compliance
    $PolicySettings = $request.body.Policy
    $ASR = $request.body.ASR
    $EDR = $request.body.EDR
    $results = foreach ($Tenant in $tenants) {
        try {
            $SettingsObj = @{
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
            } | ConvertTo-Json -Compress
            try {
                $ExistingSettings = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/fc780465-2017-40d4-a0c5-307022471b92' -tenantid $tenant
            } catch {
                $ExistingSettings = $false
            }

            if ($ExistingSettings) {
                "Defender Intune Configuration already active for $($Tenant). Skipping"
            } else {
                $SettingsRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/' -tenantid $tenant -type POST -body $SettingsObj -AsApp $true
                "$($Tenant): Successfully set Defender Compliance and Reporting settings"
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
                    } { $_.AllowIPS } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowintrusionpreventionsystem' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_allowintrusionpreventionsystem_1'; settingValueTemplateReference = @{settingValueTemplateId = '03738a99-7065-44cb-ba1e-93530ed906a7' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'd47f06e2-5378-43f2-adbc-e924538f1512' } } }
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
                    } { $_.CheckSig } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_checkforsignaturesbeforerunningscan' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_checkforsignaturesbeforerunningscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = '010779d1-edd4-441d-8034-89ad57a863fe' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = '4fea56e3-7bb6-4ad3-88c6-e364dd2f97b9' } } }
                    } { $_.DisableCatchupFullScan } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_disablecatchupfullscan'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_disablecatchupfullscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = '1b26092f-48c4-447b-99d4-e9c501542f1c' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f881b08c-f047-40d2-b7d9-3dde7ce9ef64' } } }
                    } { $_.DisableCatchupQuickScan } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_disablecatchupquickscan' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_disablecatchupquickscan_1' ; settingValueTemplateReference = @{settingValueTemplateId = 'd263ced7-0d23-4095-9326-99c8b3f5d35b' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'dabf6781-9d5d-42da-822a-d4327aa2bdd1' } } }
                    } { $_.NetworkProtectionBlock } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting'; settingInstance = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_enablenetworkprotection' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_enablenetworkprotection_1' ; settingValueTemplateReference = @{settingValueTemplateId = 'ee58fb51-9ae5-408b-9406-b92b643f388a' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'f53ab20e-8af6-48f5-9fa1-46863e1e517e' } } }
                    } { $_.LowCPU } {
                        @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSetting' ; settingInstance = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_enablelowcpupriority' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_enablelowcpupriority_1' ; settingValueTemplateReference = @{settingValueTemplateId = '045a4a13-deee-4e24-9fe4-985c9357680d' } } ; settingInstanceTemplateReference = @{settingInstanceTemplateId = 'cdeb96cf-18f5-4477-a710-0ea9ecc618af' } } }
                    }
                }
                $CheckExisting = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant
                Write-Host ($CheckExisting | ConvertTo-Json)
                if ('Default AV Policy' -in $CheckExisting.Name) {
                    "$($Tenant): AV Policy already exists. Skipping"
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
                        $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($PolicyRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $($PolicySettings.AssignTo)" -Sev 'Info'
                    }
                    "$($Tenant): Successfully set Default AV Policy settings"
                }
            }
            if ($ASR) {
                $ASRSettings = switch ($ASR) {
                    { $_.BlockAdobeChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses_block' } } }
                    { $_.BlockWin32Macro } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockadobereaderfromcreatingchildprocesses_block' } } }
                    { $_.BlockCredentialStealing } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem_block' } } }
                    { $_.BlockPSExec } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands_block' } } }
                    { $_.WMIPersistence } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription_block' } } }
                    { $_.BlockOfficeExes } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent_block' } } }
                    { $_.BlockOfficeApps } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses_block' } } }
                    { $_.BlockYoungExe } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablefilesrunningunlesstheymeetprevalenceagetrustedlistcriterion_block' } } }
                    { $_.blockJSVB } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent_block' } } }
                    { $_.blockOfficeComChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses' ; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses_block' } } }
                    { $_.blockOfficeChild } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses_block' } } }
                    { $_.BlockUntrustedUSB } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' ; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb_block' } } }
                    { $_.EnableRansomwareVac } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_useadvancedprotectionagainstransomware'; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_useadvancedprotectionagainstransomware_block' } } }
                    { $_.BlockExesMail } { @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail' ; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue' ; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail_block' } } }
                    { $_.BlockUnsignedDrivers } { @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers'; choiceSettingValue = @{'@odata.type' = '#microsoft.graph.deviceManagementConfigurationchoiceSettingValue'; value = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers_block' } } }

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
                                groupSettingCollectionValue      = @(@{children = $asrSettings })
                                settingInstanceTemplateReference = @{settingInstanceTemplateId = '19600663-e264-4c02-8f55-f2983216d6d7' }
                            }
                        })
                }
                $CheckExististingASR = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant
                if ('ASR Default rules' -in $CheckExististingASR.Name) {
                    "$($Tenant): ASR Policy already exists. Skipping"
                } else {
                    Write-Host $ASRbody
                    if (($ASRSettings | Measure-Object).Count -gt 0) {
                        $ASRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $ASRbody
                        Write-Host ($ASRRequest.id)
                        if ($ASR.AssignTo -and $ASR.AssignTo -ne 'none') {
                            $AssignBody = if ($ASR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($asr.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                            $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ASRRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Assigned policy $($Displayname) to $($ASR.AssignTo)" -Sev 'Info'
                        }
                        "$($Tenant): Successfully added ASR Settings"
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
                        "$($Tenant): EDR Policy already exists. Skipping"
                    } else {
                        $EDRRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $tenant -type POST -body $EDRbody
                        if ($ASR -and $ASR.AssignTo -ne 'none') {
                            $AssignBody = if ($ASR.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($asr.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
                            $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($EDRRequest.id)')/assign" -tenantid $tenant -type POST -body $AssignBody
                            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Assigned EDR policy $($Displayname) to $($ASR.AssignTo)" -Sev 'Info'
                        }
                        "$($Tenant): Successfully added EDR Settings"
                    }
                }
            }
        } catch {
            "Failed to add policy for $($Tenant): $($_.Exception.Message)"
            Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($Tenant) -message "Failed adding policy $($Displayname). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }

    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
