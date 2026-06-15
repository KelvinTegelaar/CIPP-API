function Invoke-CIPPStandardDevicePrepProfile {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DevicePrepProfile
    .SYNOPSIS
        (Label) Deploy Device Prep Profile
    .DESCRIPTION
        (Helptext) Creates and manages a Windows Autopilot Device Preparation profile for streamlined device enrollment.
        (DocsDescription) Deploys a Windows Autopilot Device Preparation profile through Intune configuration policies. This standard manages deployment mode, join type, account type, timeout, error messages, and optional device security group assignment. Optionally creates a new security group with the Intune Provisioning Client as owner.
    .NOTES
        CAT
            Device Management Standards
        TAG
            "autopilot"
            "device_prep"
            "enrollment"
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.DevicePrepProfile.ProfileName","label":"Profile Display Name","required":true}
            {"type":"textField","name":"standards.DevicePrepProfile.ProfileDescription","label":"Profile Description","required":false}
            {"type":"select","multiple":false,"name":"standards.DevicePrepProfile.DeploymentType","label":"Deployment Type","options":[{"label":"Single user","value":"0"},{"label":"Shared","value":"1"}]}
            {"type":"select","multiple":false,"name":"standards.DevicePrepProfile.JoinType","label":"Join Type","options":[{"label":"Microsoft Entra join","value":"0"},{"label":"Microsoft Entra hybrid join","value":"1"}]}
            {"type":"select","multiple":false,"name":"standards.DevicePrepProfile.AccountType","label":"Account Type","options":[{"label":"Standard user","value":"0"},{"label":"Administrator","value":"1"}]}
            {"type":"number","name":"standards.DevicePrepProfile.Timeout","label":"Timeout (minutes)","defaultValue":60}
            {"type":"textField","name":"standards.DevicePrepProfile.CustomErrorMessage","label":"Custom Error Message","required":false}
            {"type":"switch","name":"standards.DevicePrepProfile.AllowSkip","label":"Allow users to skip setup after failure","defaultValue":false}
            {"type":"switch","name":"standards.DevicePrepProfile.AllowDiagnostics","label":"Allow users to collect diagnostics","defaultValue":false}
            {"type":"textField","name":"standards.DevicePrepProfile.DeviceGroupName","label":"Device Security Group Name (wildcard match)","required":false}
            {"type":"switch","name":"standards.DevicePrepProfile.CreateNewGroup","label":"Create new group if group is not found","defaultValue":false}
            {"type":"radio","name":"standards.DevicePrepProfile.AssignTo","label":"Policy Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"All devices","value":"AllDevices"},{"label":"All users and devices","value":"AllDevicesAndUsers"}]}
        IMPACT
            High Impact
        ADDEDDATE
            2025-05-25
        POWERSHELLEQUIVALENT
            Graph API - deviceManagement/configurationPolicies
        RECOMMENDEDBY
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        REQUIREDCAPABILITIES
            "INTUNE_A"
            "MDM_Services"
            "EMS"
            "SCCM"
            "MICROSOFTINTUNEPLAN1"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'DevicePrepProfile' -TenantFilter $Tenant -Preset Intune
    if ($TestResult -eq $false) { return $true }

    $ProfileName = $Settings.ProfileName
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DevicePrepProfile: ProfileName is empty, skipping.' -sev Error
        return
    }

    # Resolve setting values
    $DeploymentMode = '0' # Device Prep only supports self-deploying mode
    $DeploymentType = $Settings.DeploymentType.value ?? $Settings.DeploymentType ?? '0'
    $JoinType = $Settings.JoinType.value ?? $Settings.JoinType ?? '0'
    $AccountType = $Settings.AccountType.value ?? $Settings.AccountType ?? '0'
    $Timeout = [int]($Settings.Timeout ?? 60)
    $CustomErrorMessage = $Settings.CustomErrorMessage ?? "Contact your organization`u{2019}s support person for help."
    $AllowSkip = if ($Settings.AllowSkip -eq $true) { '1' } else { '0' }
    $AllowDiagnostics = if ($Settings.AllowDiagnostics -eq $true) { '1' } else { '0' }
    $AssignTo = $Settings.AssignTo.value ?? $Settings.AssignTo ?? 'none'

    # Resolve device security group ID
    $DeviceGroupId = ''
    if (-not [string]::IsNullOrWhiteSpace($Settings.DeviceGroupName)) {
        $GroupName = $Settings.DeviceGroupName
        try {
            $EscapedName = $GroupName -replace "'", "''"
            $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName') and mailEnabled eq false and securityEnabled eq true")
            $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $Tenant)

            if ($MatchedGroups.Count -gt 1) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Multiple groups found matching '$GroupName', using first match '$($MatchedGroups[0].displayName)'" -sev Warning
                $DeviceGroupId = $MatchedGroups[0].id
            } elseif ($MatchedGroups.Count -eq 1) {
                $DeviceGroupId = $MatchedGroups[0].id
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Found group '$($MatchedGroups[0].displayName)' (ID: $DeviceGroupId)" -sev Info
            } elseif ($Settings.CreateNewGroup -eq $true -and $Settings.remediate -eq $true) {
                # Group not found — create it with Intune Provisioning Client as owner
                $IntuneProvisioningAppId = 'f1346770-5b25-470b-88bd-d5744ab7952c'
                $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$IntuneProvisioningAppId'&`$select=id" -tenantid $Tenant
                $SpId = $ServicePrincipal.id
                if ([string]::IsNullOrWhiteSpace($SpId)) {
                    # Service principal not found — instantiate it in the tenant
                    try {
                        $SpBody = @{ appId = $IntuneProvisioningAppId } | ConvertTo-Json -Compress
                        $CreatedSp = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $Tenant -body $SpBody -type POST
                        $SpId = $CreatedSp.id
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Created Intune Provisioning Client service principal (ID: $SpId)" -sev Info
                    } catch {
                        $SpError = Get-CippException -Exception $_
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Failed to create Intune Provisioning Client service principal: $($SpError.NormalizedError)" -sev Error -LogData $SpError
                        return
                    }
                }

                $GroupBody = @{
                    displayName         = $GroupName
                    description         = 'Device Preparation security group managed by CIPP'
                    securityEnabled     = $true
                    mailEnabled         = $false
                    mailNickname        = ($GroupName -replace '[^a-zA-Z0-9]', '') + (Get-Random -Maximum 9999)
                    'owners@odata.bind' = @(
                        "https://graph.microsoft.com/v1.0/servicePrincipals/$SpId"
                    )
                } | ConvertTo-Json -Compress -Depth 10

                $NewGroup = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $Tenant -body $GroupBody -type POST
                $DeviceGroupId = $NewGroup.id
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Created security group '$GroupName' (ID: $DeviceGroupId) with Intune Provisioning Client as owner" -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: No security group found matching '$GroupName'" -sev Warning
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Failed to resolve device group: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    # Build the expected configuration policy body
    $PolicyBody = @{
        name              = $ProfileName
        description       = $Settings.ProfileDescription ?? ''
        roleScopeTagIds   = @('0')
        platforms         = 'windows10'
        technologies      = 'enrollment'
        templateReference = @{
            templateId = '80d33118-b7b4-40d8-b15f-81be745e053f_1'
        }
        settings          = @(
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_deploymentmode'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '5180aeab-886e-4589-97d4-40855c646315' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = '5874c2f6-bcf1-463b-a9eb-bee64e2f2d82' }
                        value                         = "enrollment_autopilot_dpp_deploymentmode_$DeploymentMode"
                    }
                }
            }
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_deploymenttype'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'f4184296-fa9f-4b67-8b12-1723b3f8456b' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = 'e0af022f-37f3-4a40-916d-1ab7281c88d9' }
                        value                         = "enrollment_autopilot_dpp_deploymenttype_$DeploymentType"
                    }
                }
            }
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_jointype'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '6310e95d-6cfa-4d2f-aae0-1e7af12e2182' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = '1fa84eb3-fcfa-4ed6-9687-0f3d486402c4' }
                        value                         = "enrollment_autopilot_dpp_jointype_$JoinType"
                    }
                }
            }
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_accountype'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'd4f2a840-86d5-4162-9a08-fa8cc608b94e' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = 'bf13bb47-69ef-4e06-97c1-50c2859a49c2' }
                        value                         = "enrollment_autopilot_dpp_accountype_$AccountType"
                    }
                }
            }
            @{
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_timeout'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '6dec0657-dfb8-4906-a7ee-3ac6ee1edecb' }
                    simpleSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'
                        value                         = $Timeout
                        settingValueTemplateReference = @{ settingValueTemplateId = '0bbcce5b-a55a-4e05-821a-94bf576d6cc8' }
                    }
                }
            }
            @{
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_customerrormessage'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '2ddf0619-2b7a-46de-b29b-c6191e9dda6e' }
                    simpleSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'
                        value                         = $CustomErrorMessage
                        settingValueTemplateReference = @{ settingValueTemplateId = 'fe5002d5-fbe9-4920-9e2d-26bfc4b4cc97' }
                    }
                }
            }
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_allowskip'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = '2a71dc89-0f17-4ba9-bb27-af2521d34710' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = 'a2323e5e-ac56-4517-8847-b0a6fdb467e7' }
                        value                         = "enrollment_autopilot_dpp_allowskip_$AllowSkip"
                    }
                }
            }
            @{
                '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_allowdiagnostics'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'e2b7a81b-f243-4abd-bce3-c1856345f405' }
                    choiceSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                        children                      = @()
                        settingValueTemplateReference = @{ settingValueTemplateId = 'c59d26fd-3460-4b26-b47a-f7e202e7d5a3' }
                        value                         = "enrollment_autopilot_dpp_allowdiagnostics_$AllowDiagnostics"
                    }
                }
            }
            @{
                settingInstance = @{
                    '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                    settingDefinitionId              = 'enrollment_autopilot_dpp_devicesecuritygroupids'
                    settingInstanceTemplateReference = @{ settingInstanceTemplateId = 'a46a50ab-3076-4968-9366-75a40dde950e' }
                    simpleSettingValue               = @{
                        '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationStringSettingValue'
                        value                         = $DeviceGroupId
                        settingValueTemplateReference = @{ settingValueTemplateId = '5f7d09e1-1a90-44ad-9c9f-ad90ba509e60' }
                    }
                }
            }
        )
    }

    # Setting definition ID map for parsing current state
    $ChoiceSettingMap = @{
        'enrollment_autopilot_dpp_deploymentmode'   = 'DeploymentMode'
        'enrollment_autopilot_dpp_deploymenttype'   = 'DeploymentType'
        'enrollment_autopilot_dpp_jointype'         = 'JoinType'
        'enrollment_autopilot_dpp_accountype'       = 'AccountType'
        'enrollment_autopilot_dpp_allowskip'        = 'AllowSkip'
        'enrollment_autopilot_dpp_allowdiagnostics' = 'AllowDiagnostics'
    }
    $SimpleSettingMap = @{
        'enrollment_autopilot_dpp_timeout'                = 'Timeout'
        'enrollment_autopilot_dpp_customerrormessage'     = 'CustomErrorMessage'
        'enrollment_autopilot_dpp_devicesecuritygroupids' = 'DeviceGroupId'
    }

    # Check existing policies
    try {
        $ExistingPolicies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Failed to retrieve configuration policies: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $ExistingPolicy = $ExistingPolicies | Where-Object { $_.Name -eq $ProfileName } | Select-Object -First 1
    $PolicyExists = $null -ne $ExistingPolicy

    # Parse current settings
    $CurrentParsed = @{}
    if ($PolicyExists) {
        try {
            $PolicyDetail = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')?`$expand=settings" -tenantid $Tenant
            foreach ($Setting in $PolicyDetail.settings) {
                $Instance = $Setting.settingInstance
                $DefId = $Instance.settingDefinitionId

                if ($ChoiceSettingMap.ContainsKey($DefId)) {
                    $CurrentParsed[$ChoiceSettingMap[$DefId]] = ($Instance.choiceSettingValue.value -split '_')[-1]
                } elseif ($SimpleSettingMap.ContainsKey($DefId)) {
                    $CurrentParsed[$SimpleSettingMap[$DefId]] = $Instance.simpleSettingValue.value
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Failed to read policy settings: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        }
    }

    $CurrentValue = [PSCustomObject]@{
        PolicyExists       = $PolicyExists
        DeploymentMode     = [string]($CurrentParsed.DeploymentMode ?? '')
        DeploymentType     = [string]($CurrentParsed.DeploymentType ?? '')
        JoinType           = [string]($CurrentParsed.JoinType ?? '')
        AccountType        = [string]($CurrentParsed.AccountType ?? '')
        Timeout            = [int]($CurrentParsed.Timeout ?? 0)
        CustomErrorMessage = [string]($CurrentParsed.CustomErrorMessage ?? '')
        AllowSkip          = [string]($CurrentParsed.AllowSkip ?? '')
        AllowDiagnostics   = [string]($CurrentParsed.AllowDiagnostics ?? '')
        DeviceGroupId      = [string]($CurrentParsed.DeviceGroupId ?? '')
    }

    $ExpectedValue = [PSCustomObject]@{
        PolicyExists       = $true
        DeploymentMode     = $DeploymentMode
        DeploymentType     = $DeploymentType
        JoinType           = $JoinType
        AccountType        = $AccountType
        Timeout            = $Timeout
        CustomErrorMessage = $CustomErrorMessage
        AllowSkip          = $AllowSkip
        AllowDiagnostics   = $AllowDiagnostics
        DeviceGroupId      = $DeviceGroupId
    }

    # Determine compliance
    $StateIsCorrect = $PolicyExists
    if ($PolicyExists) {
        $PropertiesToCompare = @('DeploymentMode', 'DeploymentType', 'JoinType', 'AccountType', 'AllowSkip', 'AllowDiagnostics')
        foreach ($Prop in $PropertiesToCompare) {
            if ([string]$CurrentValue.$Prop -ne [string]$ExpectedValue.$Prop) {
                $StateIsCorrect = $false
                break
            }
        }
        if ($StateIsCorrect -and [int]$CurrentValue.Timeout -ne $ExpectedValue.Timeout) { $StateIsCorrect = $false }
        if ($StateIsCorrect -and $CurrentValue.CustomErrorMessage -ne $ExpectedValue.CustomErrorMessage) { $StateIsCorrect = $false }
        if ($StateIsCorrect -and $CurrentValue.DeviceGroupId -ne $ExpectedValue.DeviceGroupId) { $StateIsCorrect = $false }
    }

    # Remediate
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Profile '$ProfileName' already correctly configured" -sev Info
        } else {
            try {
                # Delete drifted policy before recreating
                if ($PolicyExists) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($ExistingPolicy.id)')" -tenantid $Tenant -type DELETE
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Deleted existing profile '$ProfileName' for recreation" -sev Info
                }

                $Body = $PolicyBody | ConvertTo-Json -Compress -Depth 20
                $NewPolicy = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $Tenant -body $Body -type POST

                # Assign the policy if requested
                if ($AssignTo -ne 'none' -and $NewPolicy.id) {
                    $AssignBody = switch ($AssignTo) {
                        'AllDevices' {
                            @{
                                assignments = @(
                                    @{
                                        target = @{
                                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                                        }
                                    }
                                )
                            }
                        }
                        'AllDevicesAndUsers' {
                            @{
                                assignments = @(
                                    @{
                                        target = @{
                                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                                        }
                                    }
                                    @{
                                        target = @{
                                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                                        }
                                    }
                                )
                            }
                        }
                    }
                    if ($AssignBody) {
                        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($NewPolicy.id)')/assign" -tenantid $Tenant -body ($AssignBody | ConvertTo-Json -Compress -Depth 10) -type POST
                    }
                }

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Successfully deployed profile '$ProfileName'" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Failed to deploy profile: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Profile '$ProfileName' is correctly configured" -sev Info
        } else {
            Write-StandardsAlert -message "Device Prep Profile '$ProfileName' is not correctly configured" -object $CurrentValue -tenant $Tenant -standardName 'DevicePrepProfile' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "DevicePrepProfile: Profile '$ProfileName' is not correctly configured" -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DevicePrepProfile' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DevicePrepProfile' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
