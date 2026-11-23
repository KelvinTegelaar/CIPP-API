BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicySetting.ps1')

    function New-DefinitionIndex {
        $Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Options = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Options['device_vendor_msft_defender_allowrealtimemonitoring_1'] = 'Allowed'
        $Index['device_vendor_msft_defender_allowrealtimemonitoring'] = @{ displayName = 'Allow Realtime Monitoring'; options = $Options }
        $Index['device_vendor_msft_firewall_rules'] = @{ displayName = 'Firewall Rules'; options = $null }
        $Index['device_vendor_msft_firewall_rules_name'] = @{ displayName = 'Name'; options = $null }
        $Index['device_vendor_msft_firewall_rules_localport'] = @{ displayName = 'Local Port Ranges'; options = $null }
        $Index['device_vendor_msft_child_with_category'] = @{ displayName = 'Categorised'; options = $null; categoryName = 'Defender' }
        $Index
    }

    function ConvertTo-PolicyObject([hashtable]$Data) {
        $Data | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    }
}

Describe 'ConvertTo-CIPPIntunePolicySetting' {
    Context 'settings catalog' {
        BeforeAll {
            $script:Index = New-DefinitionIndex
            $script:Policy = ConvertTo-PolicyObject @{
                id       = 'catalog-1'
                name     = 'Defender baseline'
                settings = @(
                    @{
                        id              = '0'
                        settingInstance = @{
                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                            settingDefinitionId = 'device_vendor_msft_defender_allowrealtimemonitoring'
                            choiceSettingValue  = @{
                                value    = 'device_vendor_msft_defender_allowrealtimemonitoring_1'
                                children = @(
                                    @{
                                        '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                        settingDefinitionId = 'device_vendor_msft_child_with_category'
                                        simpleSettingValue  = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'; value = 5 }
                                    }
                                )
                            }
                        }
                    }
                    @{
                        id              = '1'
                        settingInstance = @{
                            '@odata.type'               = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                            settingDefinitionId         = 'device_vendor_msft_firewall_rules'
                            groupSettingCollectionValue = @(
                                @{
                                    children = @(
                                        @{
                                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                            settingDefinitionId = 'device_vendor_msft_firewall_rules_name'
                                            simpleSettingValue  = @{ value = 'Allow RDP' }
                                        }
                                        @{
                                            '@odata.type'                = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                                            settingDefinitionId          = 'device_vendor_msft_firewall_rules_localport'
                                            simpleSettingCollectionValue = @(@{ value = '3389' }, @{ value = '3390' })
                                        }
                                    )
                                }
                                @{
                                    children = @(
                                        @{
                                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                            settingDefinitionId = 'device_vendor_msft_firewall_rules_name'
                                            simpleSettingValue  = @{ value = 'Allow SSH' }
                                        }
                                    )
                                }
                            )
                        }
                    }
                    @{
                        id              = '3'
                        settingInstance = @{
                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                            settingDefinitionId = 'device_vendor_msft_bool_false'
                            simpleSettingValue  = @{ value = $false }
                        }
                    }
                    @{
                        id              = '4'
                        settingInstance = @{
                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                            settingDefinitionId = 'device_vendor_msft_int_zero'
                            simpleSettingValue  = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'; value = 0 }
                        }
                    }
                    @{
                        id              = '2'
                        settingInstance = @{
                            '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                            settingDefinitionId = 'device_vendor_msft_unknown_secret'
                            simpleSettingValue  = @{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSecretSettingValue'; value = 'hunter2' }
                        }
                    }
                )
            }
            $script:Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'ConfigurationPolicies' -PolicyTypeName 'Device Configuration' -DefinitionIndex $script:Index)
        }

        It 'resolves the display name and the option label' {
            $Row = $script:Rows | Where-Object SettingId -eq 'device_vendor_msft_defender_allowrealtimemonitoring'
            $Row.SettingName | Should -Be 'Allow Realtime Monitoring'
            $Row.Value | Should -Be 'Allowed'
            $Row.Category | Should -Be 'Device Configuration'
        }

        It 'walks choice children and uses the catalog category when the index has one' {
            $Row = $script:Rows | Where-Object SettingId -eq 'device_vendor_msft_child_with_category'
            $Row.Value | Should -Be '5'
            $Row.Category | Should -Be 'Defender'
        }

        It 'walks every item of a group collection' {
            $Group = $script:Rows | Where-Object SettingId -eq 'device_vendor_msft_firewall_rules'
            $Group.Value | Should -Be '2 items'
            @($script:Rows | Where-Object SettingId -eq 'device_vendor_msft_firewall_rules_name').Value | Should -Be @('Allow RDP', 'Allow SSH')
            ($script:Rows | Where-Object SettingId -eq 'device_vendor_msft_firewall_rules_localport').Value | Should -Be '3389, 3390'
        }

        It 'falls back to the raw id and masks secret values' {
            $Row = $script:Rows | Where-Object SettingId -eq 'device_vendor_msft_unknown_secret'
            $Row.SettingName | Should -Be 'device_vendor_msft_unknown_secret'
            $Row.Value | Should -Be '(secret)'
        }

        It 'does not emit policy properties as settings' {
            $script:Rows.SettingId | Should -Not -Contain 'ConfigurationPolicies/name'
            $script:Rows | Should -HaveCount 9
        }

        It 'keeps false and zero values' {
            ($script:Rows | Where-Object SettingId -eq 'device_vendor_msft_bool_false').Value | Should -Be 'false'
            ($script:Rows | Where-Object SettingId -eq 'device_vendor_msft_int_zero').Value | Should -Be '0'
        }

        It 'finds children whose parent does not match the search' {
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'ConfigurationPolicies' -PolicyTypeName 'Device Configuration' -DefinitionIndex $script:Index -Search 'local port')

            $Rows.SettingId | Should -Be 'device_vendor_msft_firewall_rules_localport'
            $Rows.Value | Should -Be '3389, 3390'
        }

        It 'works without a definition index' {
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'ConfigurationPolicies' -PolicyTypeName 'Device Configuration' -DefinitionIndex $null)
            ($Rows | Where-Object SettingId -eq 'device_vendor_msft_defender_allowrealtimemonitoring').Value | Should -Be 'device_vendor_msft_defender_allowrealtimemonitoring_1'
        }
    }

    Context 'custom OMA-URI' {
        It 'emits one row per OMA setting and masks encrypted values' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type'        = '#microsoft.graph.windows10CustomConfiguration'
                id                   = 'custom-1'
                displayName          = 'Custom'
                lastModifiedDateTime = '2026-01-01T00:00:00Z'
                omaSettings          = @(
                    @{ '@odata.type' = '#microsoft.graph.omaSettingInteger'; displayName = 'Disable Cortana'; omaUri = './Vendor/MSFT/Policy/Config/Experience/AllowCortana'; value = 0 }
                    @{ '@odata.type' = '#microsoft.graph.omaSettingString'; displayName = 'Wifi key'; omaUri = './Vendor/MSFT/WiFi/Key'; value = 'plaintext'; isEncrypted = $true; secretReferenceValueId = 'ref' }
                )
            }

            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Custom')

            $Rows | Should -HaveCount 2
            $Rows[0].SettingId | Should -Be './Vendor/MSFT/Policy/Config/Experience/AllowCortana'
            $Rows[0].SettingName | Should -Be 'Disable Cortana'
            $Rows[0].Value | Should -Be '0'
            $Rows[0].Category | Should -Be 'Custom'
            $Rows[1].Value | Should -Be '(encrypted)'
        }

        It 'masks string values the cache has already decrypted' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                id            = 'custom-2'
                displayName   = 'Custom'
                omaSettings   = @(
                    @{ '@odata.type' = '#microsoft.graph.omaSettingString'; displayName = 'Decrypted'; omaUri = './Vendor/MSFT/A'; value = 'p@ssw0rd' }
                    @{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'Decrypted xml'; omaUri = './Vendor/MSFT/B'; value = 'PHNlY3JldC8+' }
                    @{ displayName = 'Untyped'; omaUri = './Vendor/MSFT/C'; value = 'secret' }
                    @{ '@odata.type' = '#microsoft.graph.omaSettingBoolean'; displayName = 'Flag'; omaUri = './Vendor/MSFT/D'; value = $true }
                    @{ '@odata.type' = '#microsoft.graph.omaSettingBoolean'; displayName = 'Off'; omaUri = './Vendor/MSFT/E'; value = $false }
                )
            }

            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Custom')

            $Rows.Value | Should -Be @('(encrypted)', '(encrypted)', '(encrypted)', 'true', 'false')
            ($Rows | ConvertTo-Json -Compress) | Should -Not -Match 'p@ssw0rd|PHNlY3JldC8|"secret"'
        }
    }

    Context 'property-based policies' {
        BeforeAll {
            $script:Policy = ConvertTo-PolicyObject @{
                '@odata.type'                                 = '#microsoft.graph.windows10GeneralConfiguration'
                'assignments@odata.context'                   = 'https://graph.microsoft.com/beta/$metadata#assignments'
                id                                            = 'general-1'
                displayName                                   = 'Windows general'
                description                                   = 'desc'
                version                                       = 3
                createdDateTime                               = '2026-01-01T00:00:00Z'
                lastModifiedDateTime                          = '2026-01-02T00:00:00Z'
                roleScopeTagIds                               = @('0')
                supportsScopeTags                             = $true
                assignments                                   = @(@{ id = 'a' })
                deviceManagementApplicabilityRuleOsEdition    = @{ osEditionTypes = @('windows10Enterprise') }
                passwordMinimumLength                         = 12
                passwordRequired                              = $false
                cortanaBlocked                                = $false
                enableVPNSplitTunnel                          = $true
                defenderScanMaxCpu                            = 0
                defenderScanType                              = 'notConfigured'
                defenderSystemScanSchedule                    = 'userDefined'
                defenderPotentiallyUnwantedAppAction          = 'deviceDefault'
                edgeCookiePolicy                              = 'browserDefault'
                diagnosticsDataSubmissionMode                 = 'none'
                edgeHomepageUrls                              = @('https://a', 'https://b')
                edgeSearchEngine                              = $null
                edgeSearchEngineCustom                        = ''
                emptyList                                     = @()
                defenderDetectedMalwareActions                = @{ '@odata.type' = 'microsoft.graph.defenderDetectedMalwareActions'; lowSeverity = 'clean'; highSeverity = 'block'; severeSeverity = 'deviceDefault' }
                networkProxyServer                            = @{ address = $null; useForLocalAddresses = $false }
            }
            $script:Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration')
        }

        It 'prefixes the id with the odata type and humanises the property name' {
            $Row = $script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/passwordMinimumLength'
            $Row.SettingName | Should -Be 'Password minimum length'
            $Row.Value | Should -Be '12'
            $Row.Category | Should -Be 'Windows Configuration'
        }

        It 'keeps acronyms when humanising' {
            ($script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/enableVPNSplitTunnel').SettingName | Should -Be 'Enable VPN split tunnel'
        }

        It 'formats booleans, lists and nested objects' {
            ($script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/enableVPNSplitTunnel').Value | Should -Be 'true'
            ($script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/defenderScanMaxCpu').Value | Should -Be '0'
            ($script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/edgeHomepageUrls').Value | Should -Be 'https://a, https://b'
            $Nested = $script:Rows | Where-Object SettingId -eq 'windows10GeneralConfiguration/defenderDetectedMalwareActions/lowSeverity'
            $Nested.SettingName | Should -Be 'Defender detected malware actions > Low severity'
            $Nested.Value | Should -Be 'clean'
        }

        It 'skips metadata, unset, empty, false and default enum values' {
            $Names = $script:Rows.SettingId -replace '^windows10GeneralConfiguration/', ''
            $Names | Sort-Object | Should -Be (@(
                    'defenderDetectedMalwareActions/highSeverity'
                    'defenderDetectedMalwareActions/lowSeverity'
                    'defenderScanMaxCpu'
                    'diagnosticsDataSubmissionMode'
                    'edgeHomepageUrls'
                    'enableVPNSplitTunnel'
                    'passwordMinimumLength'
                ) | Sort-Object)
        }

        It 'does not match unset booleans when searching' {
            ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -Search 'cortana' | Should -BeNullOrEmpty
        }

        It 'falls back to the family id when the policy has no odata type' {
            $Policy = ConvertTo-PolicyObject @{ id = 'fu-1'; displayName = 'Feature'; featureUpdateVersion = 'Windows 11, version 24H2' }
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'WindowsFeatureUpdateProfiles' -PolicyTypeName 'Feature Update')
            $Rows.SettingId | Should -Be 'WindowsFeatureUpdateProfiles/featureUpdateVersion'
            $Rows.SettingName | Should -Be 'Feature update version'
        }

        It 'returns only rows matching the search on name or id' {
            $ByName = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -Search 'MINIMUM LENGTH')
            $ById = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -Search 'malwareactions/low')

            $ByName.SettingId | Should -Be 'windows10GeneralConfiguration/passwordMinimumLength'
            $ById.SettingId | Should -Be 'windows10GeneralConfiguration/defenderDetectedMalwareActions/lowSeverity'
        }

        It 'finds nested properties whose parent does not match the search' {
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -Search 'low severity')

            $Rows.SettingId | Should -Be 'windows10GeneralConfiguration/defenderDetectedMalwareActions/lowSeverity'
            $Rows.SettingName | Should -Be 'Defender detected malware actions > Low severity'
        }

        It 'masks matching secrets and leaves out the settings that do not match' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type'     = '#microsoft.graph.androidDeviceOwnerWiFiConfiguration'
                id                = 'wifi-2'
                displayName       = 'Wifi'
                preSharedKey      = 'hunter2'
                preSharedKeyIsSet = $true
                kioskModeExitCode = '1234'
                server            = @{ address = 'vpn.contoso.com'; sharedSecret = 'vpn-secret' }
            }

            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Wi-Fi' -Search 'shared')

            $Rows | Should -HaveCount 3
            ($Rows | Where-Object SettingId -EQ 'androidDeviceOwnerWiFiConfiguration/preSharedKey').Value | Should -Be '(secret)'
            ($Rows | Where-Object SettingId -EQ 'androidDeviceOwnerWiFiConfiguration/preSharedKeyIsSet').Value | Should -Be 'true'
            ($Rows | Where-Object SettingId -EQ 'androidDeviceOwnerWiFiConfiguration/server/sharedSecret').Value | Should -Be '(secret)'
        }

        It 'applies the search and the setting ids together' {
            $SettingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@('windows10GeneralConfiguration/passwordMinimumLength', 'windows10GeneralConfiguration/defenderScanMaxCpu'), [System.StringComparer]::OrdinalIgnoreCase)
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -Search 'password' -SettingIds $SettingIds)

            $Rows.SettingId | Should -Be 'windows10GeneralConfiguration/passwordMinimumLength'
        }

        It 'returns only rows with the given setting ids, matching them case-insensitively' {
            $SettingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@('WINDOWS10GENERALCONFIGURATION/PASSWORDMINIMUMLENGTH'), [System.StringComparer]::OrdinalIgnoreCase)
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $script:Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Windows Configuration' -SettingIds $SettingIds)

            $Rows.SettingId | Should -Be 'windows10GeneralConfiguration/passwordMinimumLength'
        }

        It 'masks credential properties and keeps password rules' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type'         = '#microsoft.graph.androidDeviceOwnerWiFiConfiguration'
                id                    = 'wifi-1'
                displayName           = 'Wifi'
                ssid                  = 'corp'
                preSharedKey          = 'hunter2'
                preSharedKeyIsSet     = $true
                kioskModeExitCode     = '1234'
                passwordMinimumLength = 8
                server                = @{ address = 'vpn.contoso.com'; sharedSecret = 'vpn-secret' }
            }
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Wi-Fi')
            $Value = { param($Id) ($Rows | Where-Object SettingId -eq "androidDeviceOwnerWiFiConfiguration/$Id").Value }

            & $Value 'preSharedKey' | Should -Be '(secret)'
            & $Value 'kioskModeExitCode' | Should -Be '(secret)'
            & $Value 'server/sharedSecret' | Should -Be '(secret)'
            & $Value 'preSharedKeyIsSet' | Should -Be 'true'
            & $Value 'passwordMinimumLength' | Should -Be '8'
            & $Value 'ssid' | Should -Be 'corp'
            ($Rows.Value -join ' ') | Should -Not -Match 'hunter2|1234|vpn-secret'
        }

        It 'masks credentials inside serialised lists and key/value pairs' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type'      = '#microsoft.graph.iosVpnConfiguration'
                id                 = 'vpn-1'
                displayName        = 'VPN'
                customKeyValueData = @(@{ name = 'Password'; value = 'kv-secret' }, @{ name = 'Region'; value = 'eu' })
                servers            = @(@{ address = 'a'; certificatePassword = 'cert-secret' })
            }
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'VPN')

            ($Rows.Value -join ' ') | Should -Not -Match 'kv-secret|cert-secret'
            ($Rows | Where-Object SettingId -eq 'iosVpnConfiguration/customKeyValueData').Value | Should -Match 'eu'
            ($Rows | Where-Object SettingId -eq 'iosVpnConfiguration/servers').Value | Should -Match '"address":"a"'
        }

        It 'hides custom payloads that can embed credentials' {
            $Policy = ConvertTo-PolicyObject @{
                '@odata.type'   = '#microsoft.graph.windows81WifiImportConfiguration'
                id              = 'wifi-import-1'
                displayName     = 'Imported'
                payload         = 'PGtleU1hdGVyaWFsPnNlY3JldDwva2V5TWF0ZXJpYWw+'
                payloadFileName = 'wifi.xml'
            }
            $Rows = @(ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'DeviceConfigurations' -PolicyTypeName 'Wi-Fi')

            ($Rows | Where-Object SettingId -eq 'windows81WifiImportConfiguration/payload').Value | Should -Be '(hidden)'
            ($Rows | Where-Object SettingId -eq 'windows81WifiImportConfiguration/payloadFileName').Value | Should -Be 'wifi.xml'
        }

        It 'truncates very long values' {
            $Policy = ConvertTo-PolicyObject @{ id = 'hw-1'; configurationFileContent = ('A' * 2000) }
            $Row = ConvertTo-CIPPIntunePolicySetting -Policy $Policy -URLName 'hardwareConfigurations' -PolicyTypeName 'BIOS Configuration'
            $Row.Value.Length | Should -Be 503
        }
    }
}
