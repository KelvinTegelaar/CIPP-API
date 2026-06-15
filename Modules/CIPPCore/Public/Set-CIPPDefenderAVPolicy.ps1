function Set-CIPPDefenderAVPolicy {
    <#
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter,
        $PolicySettings,
        $Headers,
        [string]$APIName,
        [switch]$TemplateOnly
    )

    # Builds a choice-type setting entry
    function New-AVChoiceSetting {
        param([string]$DefinitionId, [string]$InstanceTemplateId, [string]$ValueTemplateId, [string]$Value)
        @{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId              = $DefinitionId
                settingInstanceTemplateReference = @{ settingInstanceTemplateId = $InstanceTemplateId }
                choiceSettingValue               = @{
                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    value                         = $Value
                    settingValueTemplateReference = @{ settingValueTemplateId = $ValueTemplateId }
                }
            }
        }
    }

    # Builds an integer-type setting entry
    function New-AVIntegerSetting {
        param([string]$DefinitionId, [string]$InstanceTemplateId, [string]$ValueTemplateId, [int]$Value)
        @{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                settingDefinitionId              = $DefinitionId
                settingInstanceTemplateReference = @{
                    '@odata.type'             = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'
                    settingInstanceTemplateId = $InstanceTemplateId
                }
                simpleSettingValue               = @{
                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'
                    value                         = $Value
                    settingValueTemplateReference = @{
                        '@odata.type'          = '#microsoft.graph.deviceManagementConfigurationSettingValueTemplateReference'
                        settingValueTemplateId = $ValueTemplateId
                    }
                }
            }
        }
    }

    $DP = 'device_vendor_msft_policy_config_defender'
    $DA = 'device_vendor_msft_defender_configuration'

    # Boolean choice settings: value is always <definitionId>_1
    # property -> [definitionId, instanceTemplateId, valueTemplateId]
    $BoolChoiceMap = [ordered]@{
        ScanArchives             = @("${DP}_allowarchivescanning", '7c5c9cde-f74d-4d11-904f-de4c27f72d89', '9ead75d4-6f30-4bc5-8cc5-ab0f999d79f0')
        AllowBehavior            = @("${DP}_allowbehaviormonitoring", '8eef615a-1aa0-46f4-a25a-12cbe65de5ab', '905921da-95e2-4a10-9e30-fe5540002ce1')
        AllowCloudProtection     = @("${DP}_allowcloudprotection", '7da139f1-9b7e-407d-853a-c2e5037cdc70', '16fe8afd-67be-4c50-8619-d535451a500c')
        AllowEmailScanning       = @("${DP}_allowemailscanning", 'b0d9ee81-de6a-4750-86d7-9397961c9852', 'fdf107fd-e13b-4507-9d8f-db4d93476af9')
        AllowFullScanNetwork     = @("${DP}_allowfullscanonmappednetworkdrives", 'dac47505-f072-48d6-9f23-8d93262d58ed', '3e920b10-3773-4ac5-957e-e5573aec6d04')
        AllowFullScanRemovable   = @("${DP}_allowfullscanremovabledrivescanning", 'fb36e70b-5bc9-488a-a949-8ea3ac1634d5', '366c5727-629b-4a81-b50b-52f90282fa2c')
        AllowDownloadable        = @("${DP}_allowioavprotection", 'fa06231d-aed4-4601-b631-3a37e85b62a0', 'df4e6cbd-f7ff-41c8-88cd-fa25264a237e')
        AllowRealTime            = @("${DP}_allowrealtimemonitoring", 'f0790e28-9231-4d37-8f44-84bb47ca1b3e', '0492c452-1069-4b91-9363-93b8e006ab12')
        AllowNetwork             = @("${DP}_allowscanningnetworkfiles", 'f8f28442-0a6b-4b52-b42c-d31d9687c1cf', '7b8c858c-a17d-4623-9e20-f34b851670ce')
        AllowScriptScan          = @("${DP}_allowscriptscanning", '000cf176-949c-4c08-a5d4-90ed43718db7', 'ab9e4320-c953-4067-ac9a-be2becd06b4a')
        AllowUI                  = @("${DP}_allowuseruiaccess", '0170a900-b0bc-4ccc-b7ce-dda9be49189b', '4b6c9739-4449-4006-8e5f-3049136470ea')
        CheckSigs                = @("${DP}_checkforsignaturesbeforerunningscan", '4fea56e3-7bb6-4ad3-88c6-e364dd2f97b9', '010779d1-edd4-441d-8034-89ad57a863fe')
        DisableCatchupFullScan   = @("${DP}_disablecatchupfullscan", 'f881b08c-f047-40d2-b7d9-3dde7ce9ef64', '1b26092f-48c4-447b-99d4-e9c501542f1c')
        DisableCatchupQuickScan  = @("${DP}_disablecatchupquickscan", 'dabf6781-9d5d-42da-822a-d4327aa2bdd1', 'd263ced7-0d23-4095-9326-99c8b3f5d35b')
        LowCPU                   = @("${DP}_enablelowcpupriority", 'cdeb96cf-18f5-4477-a710-0ea9ecc618af', '045a4a13-deee-4e24-9fe4-985c9357680d')
        MeteredConnectionUpdates = @("${DA}_meteredconnectionupdates", '7e3aaffb-309f-46de-8cd7-25c1a3b19e5b', '20cf972c-be3f-4bc1-93d3-781829d55233')
        DisableLocalAdminMerge   = @("${DA}_disablelocaladminmerge", '5f9a9c65-dea7-4987-a5f5-b28cfd9762ba', '3a9774b2-3143-47eb-bbca-d73c0ace2b7e')
    }

    # Integer settings: property -> [definitionId, instanceTemplateId, valueTemplateId, defaultValue]
    $IntegerMap = [ordered]@{
        AvgCPULoadFactor        = @("${DP}_avgcpuloadfactor", '816cc03e-8f96-4cba-b14f-2658d031a79a', '37195fb1-3743-4c8e-a0ce-b6fae6fa3acd', 50)
        CloudExtendedTimeout    = @("${DP}_cloudextendedtimeout", 'f61c2788-14e4-4e80-a5a7-bf2ff5052f63', '608f1561-b603-46bd-bf5f-0b9872002f75', 50)
        SignatureUpdateInterval = @("${DP}_signatureupdateinterval", '89879f27-6b7d-44d4-a08e-0a0de3e9663d', '0af6bbed-a74a-4d08-8587-b16b10b774cb', 8)
    }

    $Settings = [System.Collections.Generic.List[object]]::new()

    # Boolean choice settings
    foreach ($Entry in $BoolChoiceMap.GetEnumerator()) {
        if ($PolicySettings.($Entry.Key)) {
            $DefId, $InstId, $ValId = $Entry.Value
            $Settings.Add((New-AVChoiceSetting -DefinitionId $DefId -InstanceTemplateId $InstId -ValueTemplateId $ValId -Value "${DefId}_1"))
        }
    }

    # Dynamic choice settings (value derived from a sub-property)
    if ($PolicySettings.EnableNetworkProtection) {
        $DefId = "${DP}_enablenetworkprotection"
        $Settings.Add((New-AVChoiceSetting -DefinitionId $DefId -InstanceTemplateId 'f53ab20e-8af6-48f5-9fa1-46863e1e517e' -ValueTemplateId 'ee58fb51-9ae5-408b-9406-b92b643f388a' -Value "${DefId}_$($PolicySettings.EnableNetworkProtection.value)"))
    }
    if ($PolicySettings.CloudBlockLevel) {
        $DefId = "${DP}_cloudblocklevel"
        $Settings.Add((New-AVChoiceSetting -DefinitionId $DefId -InstanceTemplateId 'c7a37009-c16e-4145-84c8-89a8c121fb15' -ValueTemplateId '517b4e84-e933-42b9-b92f-00e640b1a82d' -Value "${DefId}_$($PolicySettings.CloudBlockLevel.value ?? '0')"))
    }
    if ($PolicySettings.AllowOnAccessProtection) {
        $DefId = "${DP}_allowonaccessprotection"
        $Settings.Add((New-AVChoiceSetting -DefinitionId $DefId -InstanceTemplateId 'afbc322b-083c-4281-8242-ebbb91398b41' -ValueTemplateId 'ed077fee-9803-44f3-b045-aab34d8e6d52' -Value "${DefId}_$($PolicySettings.AllowOnAccessProtection.value ?? '1')"))
    }
    if ($PolicySettings.SubmitSamplesConsent) {
        $DefId = "${DP}_submitsamplesconsent"
        $Settings.Add((New-AVChoiceSetting -DefinitionId $DefId -InstanceTemplateId 'bc47ce7d-a251-4cae-a8a2-6e8384904ab7' -ValueTemplateId '826ed4b6-e04f-4975-9d23-6f0904b0d87e' -Value "${DefId}_$($PolicySettings.SubmitSamplesConsent.value ?? '2')"))
    }

    # Integer settings
    foreach ($Entry in $IntegerMap.GetEnumerator()) {
        if ($PolicySettings.($Entry.Key)) {
            $DefId, $InstId, $ValId, $Default = $Entry.Value
            $Settings.Add((New-AVIntegerSetting -DefinitionId $DefId -InstanceTemplateId $InstId -ValueTemplateId $ValId -Value ($PolicySettings.($Entry.Key) ?? $Default)))
        }
    }

    # Remediation (unique nested group structure)
    if ($PolicySettings.Remediation) {
        $RemPrefix = "${DP}_threatseveritydefaultaction"
        $RemediationChildren = @(
            if ($PolicySettings.Remediation.Low) {
                @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = "${RemPrefix}_lowseveritythreats"; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "${RemPrefix}_lowseveritythreats_$($PolicySettings.Remediation.Low.value)" } }
            }
            if ($PolicySettings.Remediation.Moderate) {
                @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = "${RemPrefix}_moderateseveritythreats"; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "${RemPrefix}_moderateseveritythreats_$($PolicySettings.Remediation.Moderate.value)" } }
            }
            if ($PolicySettings.Remediation.High) {
                @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = "${RemPrefix}_highseveritythreats"; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "${RemPrefix}_highseveritythreats_$($PolicySettings.Remediation.High.value)" } }
            }
            if ($PolicySettings.Remediation.Severe) {
                @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = "${RemPrefix}_severethreats"; choiceSettingValue = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'; value = "${RemPrefix}_severethreats_$($PolicySettings.Remediation.Severe.value)" } }
            }
        )
        $Settings.Add(@{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                    settingDefinitionId              = $RemPrefix
                    settingInstanceTemplateReference = @{
                        '@odata.type'             = '#microsoft.graph.deviceManagementConfigurationSettingInstanceTemplateReference'
                        settingInstanceTemplateId = 'f6394bc5-6486-4728-b510-555f5c161f2b'
                    }
                    groupSettingCollectionValue      = @(
                        @{
                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationGroupSettingValue'
                            children      = $RemediationChildren
                        }
                    )
                }
            })
    }

    $PolBodyObj = @{
        name              = 'Default AV Policy'
        description       = ''
        platforms         = 'windows10'
        technologies      = 'mdm,microsoftSense'
        roleScopeTagIds   = @('0')
        templateReference = @{ templateId = '804339ad-1553-4478-a742-138fb5807418_1' }
        settings          = @($Settings)
    }

    if ($TemplateOnly) { return $PolBodyObj }

    $CheckExisting = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter
    if ('Default AV Policy' -in $CheckExisting.Name) {
        "$($TenantFilter): AV Policy already exists. Skipping"
    } else {
        $PolBody = ConvertTo-Json -Depth 10 -Compress -InputObject $PolBodyObj

        $PolicyRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter -type POST -body $PolBody
        if ($PolicySettings.AssignTo -ne 'None') {
            $AssignBody = if ($PolicySettings.AssignTo -ne 'AllDevicesAndUsers') { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.' + $($PolicySettings.AssignTo) + 'AssignmentTarget"}}]}' } else { '{"assignments":[{"id":"","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"}},{"id":"","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"}}]}' }
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($PolicyRequest.id)')/assign" -tenantid $TenantFilter -type POST -body $AssignBody
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned AV policy to $($PolicySettings.AssignTo)" -Sev 'Info'
        }
        "$($TenantFilter): Successfully set Default AV Policy settings"
    }
}
