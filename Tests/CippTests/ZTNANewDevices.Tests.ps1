BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestDir = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests/ZTNA/Devices'
    foreach ($Id in '24546', '24551', '24554', '24690', '24802', '24823', '24871', '51001', '51013', '51014', '51016', '51018', '51019') {
        . (Join-Path $TestDir "Invoke-CippTestZTNA$Id.ps1")
    }

    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$Stream) $script:Data[$Type] }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) $script:Counts[$Type] }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog) $script:Licensed }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function New-Assignment { @([pscustomobject]@{ target = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }) }
    function New-GroupSettingPolicy($Name, $Platforms, $Technologies, $ChildSettingId, [switch]$Assigned) {
        [pscustomobject]@{
            name         = $Name
            platforms    = $Platforms
            technologies = $Technologies
            settings     = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ groupSettingCollectionValue = @([pscustomobject]@{ children = @([pscustomobject]@{ settingDefinitionId = $ChildSettingId }) }) } })
            assignments  = if ($Assigned) { New-Assignment } else { @() }
        }
    }
    function New-MobileDevice($Os) { [pscustomobject]@{ operatingSystem = $Os } }
    function New-AppPolicy($Type, [hashtable]$Properties) {
        $Policy = [ordered]@{ URLName = $Type; id = "id-$Type"; displayName = "$Type policy"; isAssigned = $true }
        foreach ($Key in $Properties.Keys) { $Policy[$Key] = $Properties[$Key] }
        [pscustomobject]$Policy
    }
}

Describe 'ZTNA new device tests' {
    BeforeEach {
        $script:Licensed = $true
        $script:Data = @{}
        $script:Counts = @{}
        $script:Result = $null
    }

    Describe 'ZTNA24546 Windows automatic enrollment' {
        It 'passes when the Intune MDM policy applies to <Scope>' -ForEach @(@{ Scope = 'all' }, @{ Scope = 'selected' }) {
            $script:Data['MobileDeviceManagementPolicies'] = @([pscustomobject]@{ displayName = 'Microsoft Intune'; appliesTo = $Scope })
            Invoke-CippTestZTNA24546 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when the Intune MDM policy applies to none' {
            $script:Data['MobileDeviceManagementPolicies'] = @([pscustomobject]@{ displayName = 'Microsoft Intune'; appliesTo = 'none' })
            Invoke-CippTestZTNA24546 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '❌ None'
        }
        It 'skips without cached data and is unlicensed without Entra ID P1' {
            Invoke-CippTestZTNA24546 -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
            $script:Licensed = $false
            Invoke-CippTestZTNA24546 -Tenant 't'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA24551 Windows Hello for Business' {
        BeforeEach {
            $script:Data['IntuneDeviceEnrollmentConfigurations'] = @([pscustomobject]@{ deviceEnrollmentConfigurationType = 'windowsHelloForBusiness'; state = 'notConfigured' })
        }
        It 'passes when the tenant-wide setting is enabled' {
            $script:Data['IntuneDeviceEnrollmentConfigurations'][0].state = 'enabled'
            Invoke-CippTestZTNA24551 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'passes on an assigned settings catalog policy that sets UsePassportForWork' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-GroupSettingPolicy 'WHfB' 'windows10' 'mdm' 'device_vendor_msft_passportforwork_{tenantid}_policies_usepassportforwork' -Assigned)
            Invoke-CippTestZTNA24551 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when the WHfB policy is unassigned and the tenant setting is not configured' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-GroupSettingPolicy 'WHfB' 'windows10' 'mdm' 'user_vendor_msft_passportforwork_{tenantid}_policies_usepassportforwork')
            Invoke-CippTestZTNA24551 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '❌ Not assigned'
        }
    }

    Describe 'ZTNA24554 / ZTNA24690 Apple update policies' {
        It 'passes on an assigned legacy iOS update configuration' {
            $script:Data['IntuneDeviceConfigurations'] = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.iosUpdateConfiguration'; displayName = 'iOS updates'; assignments = New-Assignment })
            Invoke-CippTestZTNA24554 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'passes on an assigned iOS DDM policy only when it uses mdm and appleRemoteManagement' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-GroupSettingPolicy 'DDM' 'iOS' 'mdm,appleRemoteManagement' 'enforcement_targetosversion' -Assigned)
            Invoke-CippTestZTNA24554 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
            $script:Data['IntuneConfigurationPolicies'] = @(New-GroupSettingPolicy 'DDM' 'iOS' 'mdm' 'enforcement_targetosversion' -Assigned)
            Invoke-CippTestZTNA24554 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'fails on an unassigned iOS update configuration' {
            $script:Data['IntuneDeviceConfigurations'] = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.iosUpdateConfiguration'; displayName = 'iOS updates'; assignments = @() })
            Invoke-CippTestZTNA24554 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'passes on an assigned macOS DDM policy using mdm alone' {
            $script:Data['IntuneConfigurationPolicies'] = @(New-GroupSettingPolicy 'DDM' 'macOS' 'mdm' 'ddm-latestsoftwareupdate_enforcelatestsoftwareupdateversion' -Assigned)
            Invoke-CippTestZTNA24690 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'does not count an iOS update configuration towards macOS' {
            $script:Data['IntuneDeviceConfigurations'] = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.iosUpdateConfiguration'; displayName = 'iOS updates'; assignments = New-Assignment })
            Invoke-CippTestZTNA24690 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    Describe 'ZTNA24802 device clean-up rules' {
        It 'passes when a rule exists' {
            $script:Data['ManagedDeviceCleanupRules'] = @([pscustomobject]@{ displayName = 'Default Policy'; deviceCleanupRulePlatformType = 'all' })
            Invoke-CippTestZTNA24802 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when the collected set is empty and skips when it was never collected' {
            $script:Counts['ManagedDeviceCleanupRules'] = @([pscustomobject]@{ DataCount = 0 })
            Invoke-CippTestZTNA24802 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Counts = @{}
            Invoke-CippTestZTNA24802 -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
        }
    }

    Describe 'ZTNA24823 Company Portal branding' {
        BeforeEach {
            $script:Default = [pscustomobject]@{ profileName = 'Default'; isDefaultProfile = $true; displayName = 'Contoso'; contactITPhoneNumber = '555'; contactITEmailAddress = 'it@contoso.com' }
            $script:Custom = [pscustomobject]@{ profileName = 'Custom'; isDefaultProfile = $false; displayName = 'Contoso'; contactITPhoneNumber = '555'; contactITEmailAddress = 'it@contoso.com' }
        }
        It 'passes when the default profile has display name, phone and email' {
            $script:Data['IntuneBrandingProfile'] = @($script:Default)
            Invoke-CippTestZTNA24823 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'investigates when only a custom profile is complete, because its assignments are not cached' {
            $script:Default.contactITPhoneNumber = $null
            $script:Data['IntuneBrandingProfile'] = @($script:Default, $script:Custom)
            Invoke-CippTestZTNA24823 -Tenant 't'
            $script:Result.Status | Should -Be 'Investigate'
        }
        It 'fails when no profile is complete' {
            $script:Default.contactITEmailAddress = $null
            $script:Data['IntuneBrandingProfile'] = @($script:Default)
            Invoke-CippTestZTNA24823 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Not configured'
        }
    }

    Describe 'ZTNA24871 Defender for Endpoint Android enrollment' {
        It 'passes when the connector is enabled with Android on' {
            $script:Data['MDEOnboarding'] = @([pscustomobject]@{ id = 'fc780465-2017-40d4-a0c5-307022471b92'; partnerState = 'enabled'; androidEnabled = $true })
            Invoke-CippTestZTNA24871 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when the connector is not enabled' {
            $script:Data['MDEOnboarding'] = @([pscustomobject]@{ id = 'fc780465-2017-40d4-a0c5-307022471b92'; partnerState = 'unresponsive'; androidEnabled = $true })
            Invoke-CippTestZTNA24871 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'fails with no connector when the collector stored the unavailable stub' {
            $script:Data['MDEOnboarding'] = @([pscustomobject]@{ partnerState = 'unavailable' })
            Invoke-CippTestZTNA24871 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'No Microsoft Defender for Endpoint Connector'
        }
    }

    Describe 'ZTNA51001 Endpoint Privilege Management' {
        BeforeEach {
            $script:Counts['IntuneConfigurationPolicies'] = @([pscustomobject]@{ DataCount = 1 })
            $script:SettingsPolicy = [pscustomobject]@{ name = 'EPM settings'; templateReference = [pscustomobject]@{ templateFamily = 'endpointSecurityEndpointPrivilegeManagement'; templateDisplayName = 'Elevation settings policy' }; assignments = New-Assignment }
            $script:RulesPolicy = [pscustomobject]@{ name = 'EPM rules'; templateReference = [pscustomobject]@{ templateFamily = 'endpointSecurityEndpointPrivilegeManagement'; templateDisplayName = 'Elevation rules policy' }; assignments = New-Assignment }
        }
        It 'passes when assigned elevation settings and elevation rules policies exist' {
            $script:Data['IntuneConfigurationPolicies'] = @($script:SettingsPolicy, $script:RulesPolicy)
            Invoke-CippTestZTNA51001 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when only the elevation settings policy is assigned' {
            $script:RulesPolicy.assignments = @()
            $script:Data['IntuneConfigurationPolicies'] = @($script:SettingsPolicy, $script:RulesPolicy)
            Invoke-CippTestZTNA51001 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'elevation settings policy is assigned but no elevation rules'
        }
        It 'fails, not unlicensed, without the Intune-EPM service plan' {
            $script:Licensed = $false
            Invoke-CippTestZTNA51001 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'Intune Suite license'
        }
    }

    Describe 'ZTNA51013 / ZTNA51014 / ZTNA51019 app protection policies' {
        It 'skips <Fn> when no iOS or Android device is enrolled' -ForEach @(@{ Fn = 'Invoke-CippTestZTNA51013' }, @{ Fn = 'Invoke-CippTestZTNA51014' }, @{ Fn = 'Invoke-CippTestZTNA51019' }) {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'Windows')
            & $Fn -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It '51013 passes when the in-scope platform blocks on auth failure, and fails when an enrolled platform has none' {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'iPadOS')
            $script:Data['IntuneAppProtectionManagedAppPolicies'] = @(New-AppPolicy 'iosManagedAppProtection' @{ appActionIfUnableToAuthenticateUser = 'wipe' })
            Invoke-CippTestZTNA51013 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match 'No Android devices enrolled'

            $script:Data['ManagedDevices'] = @((New-MobileDevice 'iPadOS'), (New-MobileDevice 'Android'))
            Invoke-CippTestZTNA51013 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It '51013 does not count a warn action or an unassigned policy' {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'iOS')
            $script:Data['IntuneAppProtectionManagedAppPolicies'] = @(
                New-AppPolicy 'iosManagedAppProtection' @{ appActionIfUnableToAuthenticateUser = 'warn' }
                New-AppPolicy 'iosManagedAppProtection' @{ appActionIfUnableToAuthenticateUser = 'block'; isAssigned = $false }
            )
            Invoke-CippTestZTNA51013 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }

        It '51014 grades iOS on device compliance and Android on attestation' {
            $script:Data['ManagedDevices'] = @((New-MobileDevice 'iOS'), (New-MobileDevice 'Android'))
            $script:Data['IntuneAppProtectionManagedAppPolicies'] = @(
                New-AppPolicy 'iosManagedAppProtection' @{ deviceComplianceRequired = $true; appActionIfDeviceComplianceRequired = 'block' }
                New-AppPolicy 'androidManagedAppProtection' @{ requiredAndroidSafetyNetDeviceAttestationType = 'none'; appActionIfAndroidSafetyNetDeviceAttestationFailed = 'block' }
            )
            Invoke-CippTestZTNA51014 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'

            $script:Data['IntuneAppProtectionManagedAppPolicies'][1].requiredAndroidSafetyNetDeviceAttestationType = 'basicIntegrity'
            Invoke-CippTestZTNA51014 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }

        It '51019 requires an online recheck of at most 30 minutes plus a PIN or org credentials (<Period>, pin <Pin>, org <Org> -> <Expected>)' -ForEach @(
            @{ Period = 'PT30M'; Pin = $true; Org = $false; Expected = 'Passed' }
            @{ Period = 'PT0S'; Pin = $false; Org = $true; Expected = 'Passed' }
            @{ Period = 'PT1H'; Pin = $true; Org = $false; Expected = 'Failed' }
            @{ Period = 'PT30M'; Pin = $false; Org = $false; Expected = 'Failed' }
            @{ Period = 'bogus'; Pin = $true; Org = $false; Expected = 'Failed' }
        ) {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'Android')
            $script:Data['IntuneAppProtectionManagedAppPolicies'] = @(New-AppPolicy 'androidManagedAppProtection' @{ periodOnlineBeforeAccessCheck = $Period; pinRequired = $Pin; organizationalCredentialsRequired = $Org })
            Invoke-CippTestZTNA51019 -Tenant 't'
            $script:Result.Status | Should -Be $Expected
        }
    }

    Describe 'ZTNA51016 PIM for Intune Administrator' {
        BeforeEach {
            $script:Role = '3a2c62db-5318-420d-8d74-23affee5d9d5'
            $script:Rules = @(
                [pscustomobject]@{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                [pscustomobject]@{ id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT8H' }
            )
            $script:Data['RoleManagementPolicies'] = @([pscustomobject]@{ roleDefinitionId = $script:Role; scopeId = '/'; scopeType = 'DirectoryRole'; rules = $script:Rules })
            $script:Data['RoleAssignmentScheduleInstances'] = @([pscustomobject]@{ roleDefinitionId = '62e90394-69f5-4237-9190-012177145e10'; principalId = 'ga'; assignmentType = 'Assigned'; endDateTime = $null; principal = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user' } })
            $script:Data['Users'] = @(
                [pscustomobject]@{ id = 'u1'; userType = 'Member'; accountEnabled = $true }
                [pscustomobject]@{ id = 'u2'; userType = 'Member'; accountEnabled = $false }
                [pscustomobject]@{ id = 'u3'; userType = 'Guest'; accountEnabled = $true }
            )
            function Add-IntuneAdmin($PrincipalId, $AssignmentType = 'Assigned', $End = $null) {
                $script:Data['RoleAssignmentScheduleInstances'] = @($script:Data['RoleAssignmentScheduleInstances']) + [pscustomobject]@{
                    roleDefinitionId = $script:Role; principalId = $PrincipalId; assignmentType = $AssignmentType; endDateTime = $End; memberType = 'Direct'
                    principal        = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; displayName = $PrincipalId }
                }
            }
        }
        It 'passes with a strict activation policy and only disabled, guest or activated holders' {
            Add-IntuneAdmin 'u2'
            Add-IntuneAdmin 'u3'
            Add-IntuneAdmin 'u1' 'Activated' '2026-11-08T00:00:00Z'
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
        }
        It 'fails when an enabled member holds standing Intune Administrator' {
            Add-IntuneAdmin 'u1'
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| u1 \| - \| Assigned \| Direct \| Permanent \| Yes \| ❌ Fail \|'
        }
        It 'treats a standing user missing from the Users cache as standing access' {
            Add-IntuneAdmin 'gone'
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'fails when activation may last longer than 8 hours or skips justification' {
            $script:Rules[1].maximumDuration = 'PT10H'
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Rules[1].maximumDuration = 'PT8H'
            $script:Rules[0].enabledRules = @('MultiFactorAuthentication')
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'fails when no policy is bound to the role and skips when PIM data is missing' {
            $script:Data['RoleManagementPolicies'][0].roleDefinitionId = 'other'
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Data['RoleManagementPolicies'] = $null
            Invoke-CippTestZTNA51016 -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
        }
    }

    Describe 'ZTNA51018 App Control for Business' {
        BeforeEach {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'Windows')
            $script:Counts['IntuneConfigurationPolicies'] = @([pscustomobject]@{ DataCount = 1 })
            $script:Policy = [pscustomobject]@{
                name              = 'WDAC'
                platforms         = 'windows10'
                templateReference = [pscustomobject]@{ templateFamily = 'endpointSecurityApplicationControl' }
                settings          = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_policy_config_applicationcontrol_policies_{policyguid}_policiesoptions'; choiceSettingValue = [pscustomobject]@{ value = 'device_vendor_msft_policy_config_applicationcontrol_built_in_controls_selected' } } })
                assignments       = New-Assignment
            }
        }
        It 'passes on an assigned Windows policy with a build option' {
            $script:Data['IntuneConfigurationPolicies'] = @($script:Policy)
            Invoke-CippTestZTNA51018 -Tenant 't'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| WDAC \| Built-in controls \| ✅ Yes \| ✅ Pass \|'
        }
        It 'fails when the policy is unassigned or has no build option' {
            $script:Policy.assignments = @()
            $script:Data['IntuneConfigurationPolicies'] = @($script:Policy)
            Invoke-CippTestZTNA51018 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
            $script:Policy.assignments = New-Assignment
            $script:Policy.settings[0].settingInstance.choiceSettingValue.value = 'something_else'
            Invoke-CippTestZTNA51018 -Tenant 't'
            $script:Result.Status | Should -Be 'Failed'
        }
        It 'skips when no Windows device is enrolled' {
            $script:Data['ManagedDevices'] = @(New-MobileDevice 'iOS')
            Invoke-CippTestZTNA51018 -Tenant 't'
            $script:Result.Status | Should -Be 'Skipped'
        }
    }
}
