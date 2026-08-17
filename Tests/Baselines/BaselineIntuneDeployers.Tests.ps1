# Backlog batch 5: the Intune policy deployers. Tests pin the parsing and gating decisions
# that fail silently - the settings catalog choice-suffix conventions, ASR presence-as-enabled,
# only-configured remediation grading, the Windows partner-data force rule, self-deploying
# mode's derivations, repair-in-place vs recreate, and the Chrome app's fingerprint gate.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp, $ContentType) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Set-CIPPDefenderAVPolicy { param($TenantFilter, $PolicySettings, $APIName) }
    function Set-CIPPDefenderASRPolicy { param($TenantFilter, $ASR, $APIName) }
    function Set-CIPPDefenderEDRPolicy { param($TenantFilter, $EDR, $APIName) }
    function Set-CIPPDefenderExclusionPolicy { param($TenantFilter, $DefenderExclusions, $APIName) }
    function Enable-CIPPMDEConnector { param($TenantFilter) }
    function Set-CIPPDefaultAPDeploymentProfile { param($TenantFilter, $DisplayName, $Description, $UserType, $DeploymentMode, $AssignTo, $DeviceNameTemplate, $AllowWhiteGlove, $CollectHash, $HideChangeAccount, $HidePrivacy, $HideTerms, $AutoKeyboard, $Language) }
    function Get-CIPPIntuneAssignmentTarget { param($AssignTo, $PolicyType) }
    function Compare-CIPPIntuneAssignments { param($ExistingAssignments, $ExpectedAssignTo, $PolicyType, $TenantFilter) }
    function Add-CIPPW32ScriptApplication { param($TenantFilter, $Properties) }
    function Set-CIPPAssignedApplication { param($ApplicationId, $TenantFilter, $GroupName, $ExcludeGroup, $Intent, $AppType, $APIName) }
    function New-CIPPApplicationCopy { param($App, $Tenant) }
    function Add-CIPPDelegatedPermission { param($RequiredResourceAccess, $ApplicationId, $TemplateId, $TenantFilter) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $TemplateId, $TenantFilter) }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-NormalizedError { param($Message) "$Message" }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('DefenderAVPolicy', 'DefenderASRPolicy', 'DefenderEDRPolicy', 'DefenderExclusionPolicy',
            'DefenderCompliancePolicy', 'AutopilotProfile', 'DevicePrepProfile', 'DeployCheckChromeExtension', 'AppDeploy')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Name}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Name}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    function New-ChoiceSetting { param($DefId, $Value) @{ settingInstance = @{ settingDefinitionId = $DefId; choiceSettingValue = @{ value = $Value } } } }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselineDefenderAVPolicyState' {
    BeforeAll {
        $DP = 'device_vendor_msft_policy_config_defender'
        $script:AvPolicy = @{ id = 'av-1'; name = 'Default AV Policy'; settings = @(
                (New-ChoiceSetting "${DP}_allowarchivescanning" "${DP}_allowarchivescanning_1")
                (New-ChoiceSetting "${DP}_allowrealtimemonitoring" "${DP}_allowrealtimemonitoring_1")
                (New-ChoiceSetting "${DP}_cloudblocklevel" "${DP}_cloudblocklevel_2")
                @{ settingInstance = @{ settingDefinitionId = "${DP}_avgcpuloadfactor"; simpleSettingValue = @{ value = 50 } } }
                @{ settingInstance = @{ settingDefinitionId = "${DP}_threatseveritydefaultaction"; groupSettingCollectionValue = @(@{ children = @(
                                @{ settingDefinitionId = "${DP}_threatseveritydefaultaction_lowseveritythreats"; choiceSettingValue = @{ value = 'x_quarantine' } }
                            ) }) } }
            ) }
    }

    It 'parses the choice-suffix conventions: _1 booleans, choice suffixes, integers, remediation children' {
        Mock New-CIPPDbRequest { @($script:AvPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ScanArchives = $true; AllowRealTime = $true; CloudBlockLevel = [PSCustomObject]@{ value = '2' }; AvgCPULoadFactor = 50; RemediationLow = 'quarantine' } }
        $Prepared = Get-CIPPBaselineDefenderAVPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.scanArchives | Should -BeTrue
        $Prepared.Current.cloudBlockLevel | Should -Be '2'
        $Prepared.Current.avgCPULoadFactor | Should -Be 50
        $Prepared.Current.remediationLow | Should -Be 'quarantine'
    }

    It 'grades a remediation action ONLY when the baseline configures it - the classic compared conditionally' {
        Mock New-CIPPDbRequest { @($script:AvPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ScanArchives = $true } }
        $Prepared = Get-CIPPBaselineDefenderAVPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'remediationLow'
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'remediationSevere'
    }

    It 'deletes the drifted policy before the helper recreates it' {
        Mock New-GraphPostRequest { }
        Mock Set-CIPPDefenderAVPolicy { 'ok' }
        Invoke-CIPPBaselineDefenderAVPolicy -Remediate ([PSCustomObject]@{ scanArchives = $true }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ policyId = 'av-1' })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $uri -like "*configurationPolicies('av-1')" }
        Should -Invoke Set-CIPPDefenderAVPolicy -Times 1 -Exactly -ParameterFilter { $PolicySettings.ScanArchives -eq $true -and -not $PolicySettings.ContainsKey('Remediation') }
    }
}

Describe 'Get-CIPPBaselineDefenderASRPolicyState' {
    BeforeAll {
        $ASR = 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules'
        $script:AsrPolicy = @{ id = 'asr-1'; name = 'ASR Default rules'; settings = @(
                @{ settingInstance = @{ settingDefinitionId = $ASR; groupSettingCollectionValue = @(@{ children = @(
                                @{ settingDefinitionId = "${ASR}_blockadobereaderfromcreatingchildprocesses"; choiceSettingValue = @{ value = 'x_block' } }
                                @{ settingDefinitionId = "${ASR}_blockrebootingmachineinsafemode"; choiceSettingValue = @{ value = 'x_block' } }
                            ) }) } }
            ) }
    }

    It 'a rule PRESENT in the group is enabled; the mode comes from the first rule' {
        Mock New-CIPPDbRequest { @($script:AsrPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Mode = 'block'; BlockAdobeChild = $true; BlockSafeMode = $true } }
        $Prepared = Get-CIPPBaselineDefenderASRPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.mode | Should -Be 'block'
        $Prepared.Current.blockAdobeChild | Should -BeTrue
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'a rule the baseline turns OFF but the policy carries is drift' {
        Mock New-CIPPDbRequest { @($script:AsrPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Mode = 'block'; BlockAdobeChild = $true; BlockSafeMode = $false } }
        $Prepared = Get-CIPPBaselineDefenderASRPolicyState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-CIPPBaselineDefenderEDRPolicyState' {
    It 'config is correct only when the configuration type is auto-from-connector' {
        Mock New-CIPPDbRequest { @(@{ id = 'edr-1'; name = 'EDR Configuration'; settings = @(
                    (New-ChoiceSetting 'device_vendor_msft_windowsadvancedthreatprotection_configurationtype' 'x_onboardingblob')
                    (New-ChoiceSetting 'device_vendor_msft_windowsadvancedthreatprotection_configuration_samplesharing' 'x_1')
                ) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ Config = $true; SampleSharing = $true } }
        $Prepared = Get-CIPPBaselineDefenderEDRPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.config | Should -BeFalse
        $Prepared.Current.sampleSharing | Should -BeTrue
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-CIPPBaselineDefenderExclusionPolicyState' {
    It 'grades the three collections as sorted sets - order never matters, extras are drift' {
        Mock New-CIPPDbRequest { @(@{ id = 'excl-1'; name = 'Default AV Exclusion Policy'; settings = @(
                    @{ settingInstance = @{ settingDefinitionId = 'device_vendor_msft_policy_config_defender_excludedpaths'; simpleSettingCollectionValue = @(@{ value = 'C:\Temp' }, @{ value = 'C:\App' }) } }
                ) } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ excludedPaths = 'C:\App, C:\Temp' } }
        $Prepared = Get-CIPPBaselineDefenderExclusionPolicyState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
        $Item2 = [PSCustomObject]@{ Variables = [PSCustomObject]@{ excludedPaths = 'C:\App' } }
        $Prepared2 = Get-CIPPBaselineDefenderExclusionPolicyState -Item $Item2 -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared2.Expected -Current $Prepared2.Current).Count | Should -BeGreaterThan 0
    }

    It 'sends ONLY the configured collections to the helper' {
        Mock New-GraphPostRequest { }
        Mock Set-CIPPDefenderExclusionPolicy { 'ok' }
        Invoke-CIPPBaselineDefenderExclusionPolicy -Remediate ([PSCustomObject]@{ excludedPaths = 'C:\Temp' }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ policyId = '' })
        Should -Invoke Set-CIPPDefenderExclusionPolicy -Times 1 -Exactly -ParameterFilter {
            $DefenderExclusions.ContainsKey('excludedPaths') -and -not $DefenderExclusions.ContainsKey('excludedExtensions') -and -not $DefenderExclusions.ContainsKey('excludedProcesses')
        }
    }
}

Describe 'Get-CIPPBaselineDefenderCompliancePolicyState' {
    It 'connecting Windows FORCES the Windows partner-data block on - Microsoft enforces it' {
        Mock New-GraphGetRequest { [PSCustomObject]@{ windowsEnabled = $true; windowsDeviceBlockedOnMissingPartnerData = $true; microsoftDefenderForEndpointAttachEnabled = $true } }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ConnectWindows = $true; windowsDeviceBlockedOnMissingPartnerData = $false } }
        $Prepared = Get-CIPPBaselineDefenderCompliancePolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.windowsDeviceBlockedOnMissingPartnerData | Should -BeTrue
        $Prepared.Expected.microsoftDefenderForEndpointAttachEnabled | Should -BeTrue
    }

    It 'a missing connector grades every surface false, not an error' {
        Mock New-GraphGetRequest { throw 'not found' }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ConnectWindows = $true } }
        $Prepared = Get-CIPPBaselineDefenderCompliancePolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.windowsEnabled | Should -BeFalse
        $Prepared.Current.connectorExists | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'refuses to write when the MDE connector cannot be enabled' {
        Mock Enable-CIPPMDEConnector { [PSCustomObject]@{ Success = $false; ErrorMessage = 'no license' } }
        Mock New-GraphPostRequest { }
        { Invoke-CIPPBaselineDefenderCompliancePolicy -Remediate ([PSCustomObject]@{ connectWindows = $true }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ connectorExists = $false }) } | Should -Throw
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}

Describe 'Get-CIPPBaselineAutopilotProfileState' {
    BeforeAll {
        $script:ApProfile = @{ id = 'ap-1'; displayName = 'CIPP Autopilot'; description = 'd'; deviceNameTemplate = ''; locale = ''
            preprovisioningAllowed = $false; hardwareHashExtractionEnabled = $true
            outOfBoxExperienceSetting = @{ deviceUsageType = 'shared'; privacySettingsHidden = $true; eulaHidden = $true; keyboardSelectionPageSkipped = $true; userType = 'standard' } }
    }

    It 'self-deploying mode forces White Glove off and drops userType from the grade' {
        Mock New-CIPPDbRequest { @($script:ApProfile | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisplayName = 'CIPP Autopilot'; Description = 'd'; SelfDeployingMode = $true; AllowWhiteGlove = $true; CollectHash = $true; HidePrivacy = $true; HideTerms = $true; AutoKeyboard = $true; NotLocalAdmin = $true } }
        $Prepared = Get-CIPPBaselineAutopilotProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.preprovisioningAllowed | Should -BeFalse
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'userType'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'an empty baseline language matches a profile with no locale' {
        Mock New-CIPPDbRequest { @($script:ApProfile | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisplayName = 'CIPP Autopilot'; Description = 'd'; SelfDeployingMode = $true; CollectHash = $true; HidePrivacy = $true; HideTerms = $true; AutoKeyboard = $true } }
        $Prepared = Get-CIPPBaselineAutopilotProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.locale | Should -Be $Prepared.Expected.locale
    }

    It 'locale grades '''' and ''os-default'' as the SAME posture in every combination - Graph flips between them by write path' {
        # Create normalizes '' to 'os-default'; update stores the literal ''. Grading them
        # apart flip-flops forever, so OS-default intent tolerates both representations.
        foreach ($Pair in @(@('', 'os-default'), @('os-default', ''), @('', ''), @('os-default', 'os-default'))) {
            $ProfileCopy = $script:ApProfile.Clone(); $ProfileCopy.locale = $Pair[1]
            Mock New-CIPPDbRequest { @($script:LocaleProfile | ConvertTo-Cached) }
            $script:LocaleProfile = $ProfileCopy
            $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisplayName = 'CIPP Autopilot'; Description = 'd'; Languages = $Pair[0]; SelfDeployingMode = $true; CollectHash = $true; HidePrivacy = $true; HideTerms = $true; AutoKeyboard = $true } }
            $Prepared = Get-CIPPBaselineAutopilotProfileState -Item $Item -TenantFilter $script:Tenant
            $Prepared.Current.locale | Should -Be $Prepared.Expected.locale -Because "configured '$($Pair[0])' vs stored '$($Pair[1])'"
        }
    }

    It 'an option-object DisplayName ({label, value}) unwraps instead of stringifying into the title' {
        # Legacy saves stored the identity as an option object; interpolating it raw
        # deployed profiles literally named '@{label=...}'.
        $script:LocaleProfile = $script:ApProfile.Clone()
        $script:LocaleProfile.displayName = 'CIPP Autopilot'
        Mock New-CIPPDbRequest { @($script:LocaleProfile | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisplayName = [PSCustomObject]@{ label = 'CIPP Autopilot'; value = 'CIPP Autopilot' }; Description = 'd'; SelfDeployingMode = $true; CollectHash = $true; HidePrivacy = $true; HideTerms = $true; AutoKeyboard = $true } }
        $Prepared = Get-CIPPBaselineAutopilotProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.displayName | Should -Be 'CIPP Autopilot'
        $Prepared.Current.profileExists | Should -BeTrue
        Mock Set-CIPPDefaultAPDeploymentProfile { }
        Invoke-CIPPBaselineAutopilotProfile -Remediate ([PSCustomObject]@{ displayName = [PSCustomObject]@{ label = 'CIPP Autopilot'; value = 'CIPP Autopilot' } }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CIPP Autopilot' }
    }

    It 'a REAL locale still grades exactly - the equivalence never blesses en-US against os-default' {
        $ProfileCopy = $script:ApProfile.Clone(); $ProfileCopy.locale = 'en-US'
        $script:LocaleProfile = $ProfileCopy
        Mock New-CIPPDbRequest { @($script:LocaleProfile | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ DisplayName = 'CIPP Autopilot'; Description = 'd'; Languages = 'os-default'; SelfDeployingMode = $true; CollectHash = $true; HidePrivacy = $true; HideTerms = $true; AutoKeyboard = $true } }
        $Prepared = Get-CIPPBaselineAutopilotProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.locale | Should -Be 'en-US'
        $Prepared.Expected.locale | Should -Be 'os-default'
    }
}

Describe 'Get-CIPPBaselineDevicePrepProfileState' {
    BeforeAll {
        $script:DppPolicy = @{ id = 'dpp-1'; name = 'CIPP Device Prep'; assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g1' } }); settings = @(
                (New-ChoiceSetting 'enrollment_autopilot_dpp_deploymentmode' 'enrollment_autopilot_dpp_deploymentmode_0')
                (New-ChoiceSetting 'enrollment_autopilot_dpp_deploymenttype' 'enrollment_autopilot_dpp_deploymenttype_0')
                (New-ChoiceSetting 'enrollment_autopilot_dpp_jointype' 'enrollment_autopilot_dpp_jointype_0')
                (New-ChoiceSetting 'enrollment_autopilot_dpp_accountype' 'enrollment_autopilot_dpp_accountype_0')
                (New-ChoiceSetting 'enrollment_autopilot_dpp_allowskip' 'enrollment_autopilot_dpp_allowskip_0')
                (New-ChoiceSetting 'enrollment_autopilot_dpp_allowdiagnostics' 'enrollment_autopilot_dpp_allowdiagnostics_0')
                @{ settingInstance = @{ settingDefinitionId = 'enrollment_autopilot_dpp_timeout'; simpleSettingValue = @{ value = 60 } } }
                @{ settingInstance = @{ settingDefinitionId = 'enrollment_autopilot_dpp_customerrormessage'; simpleSettingValue = @{ value = 'msg' } } }
                @{ settingInstance = @{ settingDefinitionId = 'enrollment_autopilot_dpp_devicesecuritygroupids'; simpleSettingValue = @{ value = '' } } }
            ) }
    }

    It 'EMPTY-STRING timeout and error message grade as the defaults the executor writes' {
        # '' survives ?? (only null falls through) and [int]'' is 0 - which graded
        # timeout 0 / message '' against the 60 / default text the executor deploys.
        Mock New-CIPPDbRequest { @($script:DppPolicy | ConvertTo-Cached) }
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Unknown = $true } }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ProfileName = 'CIPP Device Prep'; Timeout = ''; CustomErrorMessage = ''; AssignTo = 'none' } }
        $Prepared = Get-CIPPBaselineDevicePrepProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.timeout | Should -Be 60
        $Prepared.Expected.customErrorMessage | Should -Match 'support person'
    }

    It 'an UNKNOWN assignment lookup leaves the dimension out of the grade entirely' {
        Mock New-CIPPDbRequest { @($script:DppPolicy | ConvertTo-Cached) }
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Unknown = $true; Matched = $false } }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ProfileName = 'CIPP Device Prep'; CustomErrorMessage = 'msg'; AssignTo = 'AllDevicesAndUsers' } }
        $Prepared = Get-CIPPBaselineDevicePrepProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'isAssigned'
        $Prepared.Current.settingsCorrect | Should -BeTrue
    }

    It 'a readable mismatched assignment grades isAssigned false while settings stay correct' {
        Mock New-CIPPDbRequest { @($script:DppPolicy | ConvertTo-Cached) }
        Mock Compare-CIPPIntuneAssignments { [PSCustomObject]@{ Unknown = $false; Matched = $false } }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ ProfileName = 'CIPP Device Prep'; CustomErrorMessage = 'msg'; AssignTo = 'AllDevicesAndUsers' } }
        $Prepared = Get-CIPPBaselineDevicePrepProfileState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.isAssigned | Should -BeFalse
        $Prepared.Current.settingsCorrect | Should -BeTrue
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'repairs a wrong assignment IN PLACE - no delete, no recreate' {
        Mock Get-CIPPIntuneAssignmentTarget { [PSCustomObject]@{ Targets = @(@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = 'g2' }); Unsupported = $null } }
        Mock New-GraphPostRequest { }
        Mock New-GraphGetRequest { @() }
        $Remediate = [PSCustomObject]@{ profileName = 'CIPP Device Prep'; assignTo = 'AllDevicesAndUsers' }
        Invoke-CIPPBaselineDevicePrepProfile -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ policyId = 'dpp-1'; settingsCorrect = $true })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*configurationPolicies('dpp-1')/assign" -and $type -eq 'POST' }
    }

    It 'drifted settings delete and recreate with the classic''s policy body' {
        Mock Get-CIPPIntuneAssignmentTarget { [PSCustomObject]@{ Targets = @(); Unsupported = $null } }
        Mock New-GraphGetRequest { @() }
        Mock New-GraphPostRequest { [PSCustomObject]@{ id = 'dpp-new' } }
        $Remediate = [PSCustomObject]@{ profileName = 'CIPP Device Prep'; assignTo = 'none'; timeout = 90 }
        Invoke-CIPPBaselineDevicePrepProfile -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ policyId = 'dpp-1'; settingsCorrect = $false })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'POST' -and $uri -like '*configurationPolicies' -and ($body | ConvertFrom-Json).templateReference.templateId -eq '80d33118-b7b4-40d8-b15f-81be745e053f_1'
        }
    }
}

Describe 'Get-CIPPBaselineDeployCheckChromeExtensionState' {
    It 'grades presence of the Win32 app from the mobile apps cache' {
        Mock New-CIPPDbRequest { @(@{ id = 'app-1'; displayName = 'Check by CyberDrain - Browser Extension'; description = 'x [cfg:AAAABBBBCCCCDDDD]' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineDeployCheckChromeExtensionState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'the fingerprint gate SKIPS the redeploy when the config hash is unchanged' {
        # Compute the hash the executor would produce for these settings by letting it run
        # once against a non-matching app, capturing the description it deploys.
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ Value = 'cipp.example.com' } }
        Mock New-GraphGetRequest { @() }
        Mock New-GraphBulkRequest { @() }
        Mock New-GraphPostRequest { }
        $script:DeployedDescription = $null
        Mock Add-CIPPW32ScriptApplication { $script:DeployedDescription = $Properties.description; [PSCustomObject]@{ Id = 'new-app' } }
        Mock Set-CIPPAssignedApplication { }
        Mock Start-Sleep { }
        $Remediate = [PSCustomObject]@{ showNotifications = $true; assignTo = 'AllDevices' }
        Invoke-CIPPBaselineDeployCheckChromeExtension -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        Should -Invoke Add-CIPPW32ScriptApplication -Times 1 -Exactly
        $script:DeployedDescription | Should -Match '\[cfg:[0-9A-Fa-f]{16}\]'

        # Second run: the live app read returns the app with the SAME fingerprint - no
        # delete, no redeploy.
        Mock New-GraphGetRequest {
            if ($uri -like '*mobileApps*') { @([PSCustomObject]@{ id = 'app-1'; displayName = 'Check by CyberDrain - Browser Extension'; description = $script:DeployedDescription; '@odata.type' = '#microsoft.graph.win32LobApp' }) }
            else { @() }
        }
        Invoke-CIPPBaselineDeployCheckChromeExtension -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        Should -Invoke Add-CIPPW32ScriptApplication -Times 1 -Exactly
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $type -eq 'DELETE' }
    }
}

Describe 'Get-CIPPBaselineAppDeployState' {
    It 'copy mode accepts an app present by appId OR applicationTemplateId' {
        Mock New-CIPPDbRequest { @(
                (@{ appId = 'aaa'; displayName = 'App A' } | ConvertTo-Cached)
                (@{ appId = 'zzz'; applicationTemplateId = 'bbb'; displayName = 'App B' } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ mode = 'copy'; appids = 'aaa, bbb' } }
        $Prepared = Get-CIPPBaselineAppDeployState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'template mode resolves each template to its type-specific identity' {
        Mock New-CIPPDbRequest { @((@{ appId = 'ent-1'; displayName = 'SomethingElse' } | ConvertTo-Cached)) }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*'t-manifest'") { [PSCustomObject]@{ JSON = '{"AppType":"ApplicationManifest","AppName":"Manifest App"}' } }
            else { [PSCustomObject]@{ JSON = '{"AppType":"EnterpriseApp","AppId":"ent-1","AppName":"Enterprise App"}' } }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ mode = [PSCustomObject]@{ value = 'template' }; templateIds = @([PSCustomObject]@{ value = 't-manifest' }, [PSCustomObject]@{ value = 't-ent' }) } }
        $Prepared = Get-CIPPBaselineAppDeployState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.missingApps) | Should -Contain 'Manifest App'
        @($Prepared.Current.missingApps) | Should -Not -Contain 'Enterprise App'
    }

    It 'copy mode remediation copies each configured app and continues past failures' {
        Mock New-CIPPDbRequest { @((@{ appId = 'aaa'; displayName = 'App A' } | ConvertTo-Cached)) }
        Mock New-CIPPApplicationCopy { if ($App -eq 'aaa') { throw 'boom' } }
        Invoke-CIPPBaselineAppDeploy -Remediate ([PSCustomObject]@{ mode = 'copy'; appids = 'aaa,bbb' }) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-CIPPApplicationCopy -Times 2 -Exactly
    }
}
