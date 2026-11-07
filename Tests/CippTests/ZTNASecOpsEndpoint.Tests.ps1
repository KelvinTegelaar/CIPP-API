BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestsRoot = Join-Path $RepoRoot 'Modules/CIPPTests/Public'
    . (Join-Path $TestsRoot 'Helpers/Get-CippIntuneSettingInstance.ps1')
    . (Join-Path $TestsRoot 'Helpers/Get-CippTestSecureScoreControl.ps1')
    foreach ($Id in '41049', '41050', '41051', '41052', '41053', '41054', '41055', '41059', '41060', '41119') {
        . (Join-Path $TestsRoot "Tests/ZTNA/Devices/Invoke-CippTestZTNA$Id.ps1")
    }
    foreach ($Id in '41080', '41083') {
        . (Join-Path $TestsRoot "Tests/ZTNA/Identity/Invoke-CippTestZTNA$Id.ps1")
    }

    function Get-CIPPTestData { param($TenantFilter, $Type) $script:Data[$Type] }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown"; TestType = $TestType } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog) $script:Licensed }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function Invoke-Verdict($Id) {
        & "Invoke-CippTestZTNA$Id" -Tenant 'contoso.com'
        $script:Result.Status
    }
    function New-ControlProfile($Id, $Max = 8, $State = 'Default') {
        [pscustomobject]@{ id = $Id; service = 'MDATP'; title = "Control $Id"; maxScore = $Max; controlStateUpdates = @([pscustomobject]@{ state = $State; updatedDateTime = $null }) }
    }
    function Set-SecureScore([hashtable]$Scores, [string[]]$Ignored = @(), [string[]]$NoProfile = @()) {
        $Ids = @('scid_96', 'scid_2021', 'scid_2012', 'scid_91', 'scid_92', 'scid_89', 'scid_90', 'scid_5093', 'scid_6093', 'scid_2004', 'scid_2016', 'scid_5094', 'scid_6094') + @(foreach ($N in 2500..2518) { "scid_$N" })
        $script:Data['SecureScoreControlProfiles'] = @(foreach ($Id in $Ids) { if ($Id -notin $NoProfile) { New-ControlProfile $Id 8 $(if ($Id -in $Ignored) { 'Ignored' } else { 'Default' }) } })
        $script:Data['SecureScore'] = @(
            [pscustomobject]@{ createdDateTime = '2026-11-01T00:00:00Z'; controlScores = @(foreach ($Id in $Ids) { [pscustomobject]@{ controlName = $Id; score = 8 } }) }
            [pscustomobject]@{ createdDateTime = '2026-11-06T00:00:00Z'; controlScores = @(foreach ($Key in $Scores.Keys) { [pscustomobject]@{ controlName = $Key; score = $Scores[$Key]; implementationStatus = 'status' } }) }
        )
    }
    function New-ScPolicy($Name, $Instances, $Assignments = @(), $Family = 'none', $Technologies = 'mdm') {
        [pscustomobject]@{
            id = "id-$Name"; name = $Name; technologies = $Technologies; platforms = 'windows10'; lastModifiedDateTime = '2026-11-01T00:00:00Z'
            templateReference = [pscustomobject]@{ templateFamily = $Family; templateId = 't1' }
            assignments = @($Assignments); settings = @(foreach ($I in $Instances) { [pscustomobject]@{ settingInstance = $I } })
        }
    }
    function New-Choice($Id, $Value, $Children = @()) { [pscustomobject]@{ settingDefinitionId = $Id; choiceSettingValue = [pscustomobject]@{ value = $Value; children = @($Children) } } }
    function New-Target($Type = 'groupAssignmentTarget') { [pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$Type" } } }
}

Describe 'ZTNA SecOps endpoint and identity threat tests' {
    BeforeEach {
        $script:Licensed = $true
        $script:Data = @{}
    }

    Describe 'Secure Score Defender for Endpoint tests' {
        It 'reports Unlicensed without a Defender for Endpoint licence' {
            $script:Licensed = $false
            Set-SecureScore @{}
            Invoke-Verdict '41050' | Should -Be 'Unlicensed'
        }

        It 'skips when no Secure Score is cached' {
            Invoke-Verdict '41054' | Should -Be 'Skipped'
        }

        It 'grades every pinned control on the latest snapshot only' {
            $AllAsr = @{}; foreach ($N in 2500..2518) { $AllAsr["scid_$N"] = 9 }
            Set-SecureScore $AllAsr
            Invoke-Verdict '41050' | Should -Be 'Passed'
            $script:Result.TestType | Should -Be 'Devices'

            $AllAsr['scid_2507'] = 3
            Set-SecureScore $AllAsr
            Invoke-Verdict '41050' | Should -Be 'Failed'

            Set-SecureScore @{}
            Invoke-Verdict '41050' | Should -Be 'Investigate'
            $script:Result.Markdown | Should -Match 'no applicable devices'
        }

        It 'ranks Investigate above Pass for the antivirus controls' {
            Set-SecureScore @{ scid_2012 = 10; scid_91 = 'n/a' }
            Invoke-Verdict '41055' | Should -Be 'Investigate'
            Set-SecureScore @{ scid_2012 = 10; scid_91 = 8 }
            Invoke-Verdict '41055' | Should -Be 'Passed'
            Set-SecureScore @{ scid_2012 = 10; scid_91 = 1 }
            Invoke-Verdict '41055' | Should -Be 'Failed'
        }

        It 'treats an ignored control as Investigate for controlled folder access and as Failed for network protection and EDR block mode' {
            Set-SecureScore @{ scid_2021 = 8; scid_96 = 8; scid_2004 = 8 } -Ignored 'scid_2021', 'scid_96', 'scid_2004'
            Invoke-Verdict '41054' | Should -Be 'Investigate'
            Invoke-Verdict '41053' | Should -Be 'Failed'
            Invoke-Verdict '41059' | Should -Be 'Failed'
        }

        It 'passes, fails and investigates single-control tests from the score' {
            Set-SecureScore @{ scid_2021 = 8; scid_96 = 8; scid_2004 = 8 }
            Invoke-Verdict '41054' | Should -Be 'Passed'
            Invoke-Verdict '41053' | Should -Be 'Passed'
            Invoke-Verdict '41059' | Should -Be 'Passed'

            Set-SecureScore @{ scid_2021 = 2; scid_96 = 2; scid_2004 = 2 }
            Invoke-Verdict '41054' | Should -Be 'Failed'
            Invoke-Verdict '41053' | Should -Be 'Failed'
            Invoke-Verdict '41059' | Should -Be 'Failed'

            Set-SecureScore @{}
            Invoke-Verdict '41053' | Should -Be 'Investigate'
            Invoke-Verdict '41059' | Should -Be 'Investigate'
        }

        It 'requires every returned cloud protection control to be fully scored' {
            Set-SecureScore @{ scid_2016 = 8; scid_5094 = 8 } -NoProfile 'scid_6094'
            Invoke-Verdict '41060' | Should -Be 'Passed'

            Set-SecureScore @{ scid_2016 = 8 }
            Invoke-Verdict '41060' | Should -Be 'Failed'

            Set-SecureScore @{} -NoProfile 'scid_2016', 'scid_5094', 'scid_6094'
            Invoke-Verdict '41060' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41049 Defender Antivirus UI hidden' {
        It 'passes on an assigned policy that hides the virus UI in a nested setting' {
            $Group = [pscustomobject]@{ settingDefinitionId = 'group'; groupSettingCollectionValue = @([pscustomobject]@{ children = @(New-Choice 'device_vendor_msft_policy_config_windowsdefendersecuritycenter_disablevirusui' 'device_vendor_msft_policy_config_windowsdefendersecuritycenter_disablevirusui_1') }) }
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'Hide UI' @($Group) @(New-Target))
            Invoke-Verdict '41049' | Should -Be 'Passed'
        }

        It 'fails when the virus UI is hidden only in an unassigned policy' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'Hide UI' @(New-Choice 'x_disablevirusui' 'x_disablevirusui_1'))
            Invoke-Verdict '41049' | Should -Be 'Failed'
        }

        It 'falls back to legacy endpoint protection profiles when Settings Catalog has no virus UI control' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'Other' @(New-Choice 'x_disablefamilyui' 'x_disablefamilyui_1') @(New-Target))
            $script:Data['IntuneDeviceConfigurations'] = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.windows10EndpointProtectionConfiguration'; displayName = 'EPP'; assignments = @(New-Target); defenderSecurityCenterDisableVirusUI = $true; defenderSecurityCenterNotificationsFromApp = 'notConfigured' })
            Invoke-Verdict '41049' | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'Legacy EPP'
        }

        It 'investigates when no surface configures the virus UI' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'Other' @(New-Choice 'x_disablefamilyui' 'x_disablefamilyui_1') @(New-Target))
            Invoke-Verdict '41049' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41051 device control' {
        It 'passes when a device control policy has an inclusive assignment' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'DC' @(New-Choice 'device_vendor_msft_defender_configuration_devicecontrol_policyrules' 'x') @(New-Target 'allDevicesAssignmentTarget'))
            Invoke-Verdict '41051' | Should -Be 'Passed'
        }

        It 'fails when the only assignment is an exclusion' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'DC' @(New-Choice 'device_vendor_msft_policy_config_storage_removablediskdenywriteaccess' 'x') @(New-Target 'exclusionGroupAssignmentTarget'))
            Invoke-Verdict '41051' | Should -Be 'Failed'
        }

        It 'investigates when no device control policy exists' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'Audit' @(New-Choice 'device_vendor_msft_policy_config_audit_objectaccess_auditremovablestorage' 'x') @(New-Target))
            Invoke-Verdict '41051' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41052 App Control for Business' {
        BeforeAll {
            function New-AppControl($Mode, $Assignments = @(New-Target)) {
                $Enable = New-Choice 'device_vendor_msft_policy_config_applicationcontrol_enable_app_control' "device_vendor_msft_policy_config_applicationcontrol_enable_app_control_$Mode"
                $Build = New-Choice 'device_vendor_msft_policy_config_applicationcontrol_built_in_controls' 'device_vendor_msft_policy_config_applicationcontrol_built_in_controls_selected' @($Enable)
                New-ScPolicy "AC $Mode" @($Build) $Assignments 'endpointSecurityApplicationControl'
            }
            function New-XmlAppControl($Options) {
                $Xml = "<SiPolicy xmlns='urn:schemas-microsoft-com:sipolicy'><PolicyType>Base Policy</PolicyType><Rules>$(foreach ($O in $Options) { "<Rule><Option>$O</Option></Rule>" })</Rules></SiPolicy>"
                $Encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Xml))
                $XmlSetting = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_policy_config_applicationcontrol_policies_{policyguid}_xml'; simpleSettingValue = [pscustomobject]@{ value = $Encoded } }
                $Build = New-Choice 'device_vendor_msft_policy_config_applicationcontrol_configure_xml' 'device_vendor_msft_policy_config_applicationcontrol_configure_xml_selected' @($XmlSetting)
                New-ScPolicy 'AC xml' @($Build) @(New-Target) 'endpointSecurityApplicationControl'
            }
        }

        It 'passes on an assigned enforced built-in policy and fails on audit-only' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-AppControl 'enabled')
            Invoke-Verdict '41052' | Should -Be 'Passed'
            $script:Data['IntuneConfigurationPolicies'] = @(New-AppControl 'audit_only')
            Invoke-Verdict '41052' | Should -Be 'Failed'
        }

        It 'fails an enforced policy that is not assigned' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-AppControl 'enabled' @())
            Invoke-Verdict '41052' | Should -Be 'Failed'
        }

        It 'reads the enforcement mode from a Base64 policy XML' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-XmlAppControl @('Enabled:UMCI'))
            Invoke-Verdict '41052' | Should -Be 'Passed'
            $script:Data['IntuneConfigurationPolicies'] = @(New-XmlAppControl @('Enabled:UMCI', 'Enabled:Audit Mode'))
            Invoke-Verdict '41052' | Should -Be 'Failed'
        }

        It 'investigates an assigned policy whose mode cannot be read' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'AC' @() @(New-Target) 'endpointSecurityApplicationControl')
            Invoke-Verdict '41052' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41119 DisableLocalAdminMerge' {
        BeforeAll {
            $script:Merge = 'device_vendor_msft_defender_configuration_disablelocaladminmerge'
        }

        It 'passes on an assigned policy that sets the control to yes' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'AV' @(New-Choice $script:Merge "$($script:Merge)_1") @(New-Target 'allDevicesAssignmentTarget'))
            Invoke-Verdict '41119' | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'allDevices'
        }

        It 'fails when any policy sets no, even beside a passing one' {
            $script:Data['IntuneConfigurationPolicies'] = @(
                New-ScPolicy 'AV1' @(New-Choice $script:Merge "$($script:Merge)_1") @(New-Target)
                New-ScPolicy 'AV2' @(New-Choice $script:Merge "$($script:Merge)_0") @(New-Target)
            )
            Invoke-Verdict '41119' | Should -Be 'Failed'
        }

        It 'fails when the control is set to yes only in an unassigned policy' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'AV' @(New-Choice $script:Merge "$($script:Merge)_1"))
            Invoke-Verdict '41119' | Should -Be 'Failed'
        }

        It 'investigates when no policy carries the control, and ignores non-MDM policies' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-ScPolicy 'AV' @(New-Choice $script:Merge "$($script:Merge)_1") @(New-Target) 'none' 'microsoftSense')
            Invoke-Verdict '41119' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41080 Conditional Access App Control' {
        BeforeAll {
            function New-CaPolicy($State, $Type, $Apps = @('All')) {
                [pscustomobject]@{ id = 'p1'; displayName = 'MDCA'; state = $State; conditions = [pscustomobject]@{ applications = [pscustomobject]@{ includeApplications = $Apps } }; sessionControls = [pscustomobject]@{ cloudAppSecurity = [pscustomobject]@{ isEnabled = $true; cloudAppSecurityType = $Type } } }
            }
        }

        It 'passes on an enabled policy with MDCA session control' {
            $script:Data['ConditionalAccessPolicies'] = @(New-CaPolicy 'enabled' 'mcasConfigured')
            Invoke-Verdict '41080' | Should -Be 'Passed'
            $script:Result.TestType | Should -Be 'Identity'
        }

        It 'ignores report-only policies and policies without target apps' {
            $script:Data['ConditionalAccessPolicies'] = @((New-CaPolicy 'enabledForReportingButNotEnforced' 'mcasConfigured'), (New-CaPolicy 'enabled' 'mcasConfigured' @()))
            Invoke-Verdict '41080' | Should -Be 'Failed'
        }

        It 'investigates when every match has an unknown session type' {
            $script:Data['ConditionalAccessPolicies'] = @(New-CaPolicy 'enabled' 'unknownFutureValue')
            Invoke-Verdict '41080' | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA41083 risk-based step-up authentication' {
        BeforeAll {
            function New-RiskPolicy($StrengthId, $Combinations = @(), $BuiltIn = @(), $Operator = 'OR') {
                $Strength = if ($StrengthId) { [pscustomobject]@{ id = $StrengthId; displayName = 'Strength'; allowedCombinations = $Combinations } }
                [pscustomobject]@{
                    id = 'p1'; displayName = 'Risk'; state = 'enabled'
                    conditions = [pscustomobject]@{ signInRiskLevels = @('high', 'medium'); userRiskLevels = @() }
                    grantControls = [pscustomobject]@{ operator = $Operator; builtInControls = $BuiltIn; authenticationStrength = $Strength }
                }
            }
        }

        It 'passes with the built-in phishing-resistant strength' {
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy '00000000-0000-0000-0000-000000000004')
            Invoke-Verdict '41083' | Should -Be 'Passed'
        }

        It 'resolves a custom strength from the cached authentication strengths' {
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy 'custom')
            $script:Data['AuthenticationStrengths'] = @([pscustomobject]@{ id = 'custom'; allowedCombinations = @('fido2', 'windowsHelloForBusiness') })
            Invoke-Verdict '41083' | Should -Be 'Passed'
        }

        It 'investigates a custom strength whose combinations cannot be found' {
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy 'custom')
            Invoke-Verdict '41083' | Should -Be 'Investigate'
        }

        It 'fails when a weaker method or an OR alternative satisfies the grant' {
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy 'custom' @('fido2', 'password,sms'))
            Invoke-Verdict '41083' | Should -Be 'Failed'
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy '00000000-0000-0000-0000-000000000004' @() @('mfa'))
            Invoke-Verdict '41083' | Should -Be 'Failed'
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy '00000000-0000-0000-0000-000000000004' @() @('mfa') 'AND')
            Invoke-Verdict '41083' | Should -Be 'Passed'
        }

        It 'reports Unlicensed without Entra ID P2 and Defender for Cloud Apps' {
            $script:Licensed = $false
            $script:Data['ConditionalAccessPolicies'] = @(New-RiskPolicy '00000000-0000-0000-0000-000000000004')
            Invoke-Verdict '41083' | Should -Be 'Unlicensed'
        }
    }
}
