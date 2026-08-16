function Invoke-CIPPBaselineDevicePrepProfile {
    <#
    .SYNOPSIS
        DevicePrepProfile executor: deploys the named Device Preparation profile.
    .DESCRIPTION
        The classic's three-way write. Settings correct but assignment wrong: repair the
        assignment IN PLACE through /assign - recreating would sever the enrollment-time
        device group linkage over a delta the endpoint can fix. Otherwise: delete the drifted
        profile and recreate it with the classic's exact settings body, resolving (or, when
        CreateNewGroup allows, creating with the Intune Provisioning Client as owner) the
        device security group first.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $ProfileName = "$($Remediate.profileName)"
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { return }

    $DeploymentMode = '0' # Device Prep only supports self-deploying mode
    $DeploymentType = [string]($Remediate.deploymentType.value ?? $Remediate.deploymentType ?? '0')
    $JoinType = [string]($Remediate.joinType.value ?? $Remediate.joinType ?? '0')
    $AccountType = [string]($Remediate.accountType.value ?? $Remediate.accountType ?? '0')
    $Timeout = [int]"$($Remediate.timeout ?? 60)"
    $CustomErrorMessage = "$($Remediate.customErrorMessage ?? "Contact your organization$([char]0x2019)s support person for help.")"
    $AllowSkip = $(if ($Remediate.allowSkip -eq $true) { '1' } else { '0' })
    $AllowDiagnostics = $(if ($Remediate.allowDiagnostics -eq $true) { '1' } else { '0' })
    $AssignTo = [string]($Remediate.assignTo.value ?? $Remediate.assignTo ?? 'none')

    $AssignmentTarget = Get-CIPPIntuneAssignmentTarget -AssignTo $AssignTo -PolicyType 'DevicePrepProfile'
    $AssignmentBody = if (@($AssignmentTarget.Targets).Count -gt 0) {
        @{ assignments = @($AssignmentTarget.Targets | ForEach-Object { @{ target = $_ } }) } | ConvertTo-Json -Compress -Depth 10
    }
    if ($AssignmentTarget.Unsupported) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "DevicePrepProfile: $($AssignmentTarget.Unsupported)" -Sev 'Warning'
    }

    # Settings already correct means only the assignment drifted: repair it in place.
    if ($Current.settingsCorrect -eq $true -and -not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        if ($AssignmentBody) {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Current.policyId)')/assign" -tenantid $TenantFilter -body $AssignmentBody -type POST
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Repaired the assignment for Device Prep profile '$ProfileName'." -Sev 'Info'
        }
        return
    }

    # Resolve or create the device security group, the classic's flow.
    $DeviceGroupId = ''
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.deviceGroupName)")) {
        $GroupName = "$($Remediate.deviceGroupName)"
        $EscapedName = $GroupName -replace "'", "''"
        $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName') and mailEnabled eq false and securityEnabled eq true")
        $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $TenantFilter)
        if ($MatchedGroups.Count -gt 0) {
            $DeviceGroupId = "$($MatchedGroups[0].id)"
        } elseif ($Remediate.createNewGroup -eq $true) {
            $IntuneProvisioningAppId = 'f1346770-5b25-470b-88bd-d5744ab7952c'
            $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$IntuneProvisioningAppId'&`$select=id" -tenantid $TenantFilter
            $SpId = "$($ServicePrincipal.id)"
            if ([string]::IsNullOrWhiteSpace($SpId)) {
                $SpBody = @{ appId = $IntuneProvisioningAppId } | ConvertTo-Json -Compress
                $CreatedSp = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -body $SpBody -type POST
                $SpId = "$($CreatedSp.id)"
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Created the Intune Provisioning Client service principal.' -Sev 'Info'
            }
            $GroupBody = @{
                displayName         = $GroupName
                description         = 'Device Preparation security group managed by CIPP'
                securityEnabled     = $true
                mailEnabled         = $false
                mailNickname        = ($GroupName -replace '[^a-zA-Z0-9]', '') + (Get-Random -Maximum 9999)
                'owners@odata.bind' = @("https://graph.microsoft.com/v1.0/servicePrincipals/$SpId")
            } | ConvertTo-Json -Compress -Depth 10
            $NewGroup = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -body $GroupBody -type POST
            $DeviceGroupId = "$($NewGroup.id)"
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created the security group '$GroupName' with the Intune Provisioning Client as owner." -Sev 'Info'
        } else {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "DevicePrepProfile: no security group found matching '$GroupName'." -Sev 'Warning'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Current.policyId)')" -tenantid $TenantFilter -type DELETE
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deleted the drifted Device Prep profile '$ProfileName' for recreation." -Sev 'Info'
    }

    $Choice = { param($DefId, $InstanceTemplate, $ValueTemplate, $Value)
        @{
            '@odata.type'   = '#microsoft.graph.deviceManagementConfigurationSetting'
            settingInstance = @{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId              = $DefId
                settingInstanceTemplateReference = @{ settingInstanceTemplateId = $InstanceTemplate }
                choiceSettingValue               = @{
                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationChoiceSettingValue'
                    children                      = @()
                    settingValueTemplateReference = @{ settingValueTemplateId = $ValueTemplate }
                    value                         = $Value
                }
            }
        }
    }
    $PolicyBody = @{
        name              = $ProfileName
        description       = "$($Remediate.profileDescription ?? '')"
        roleScopeTagIds   = @('0')
        platforms         = 'windows10'
        technologies      = 'enrollment'
        templateReference = @{ templateId = '80d33118-b7b4-40d8-b15f-81be745e053f_1' }
        settings          = @(
            (& $Choice 'enrollment_autopilot_dpp_deploymentmode' '5180aeab-886e-4589-97d4-40855c646315' '5874c2f6-bcf1-463b-a9eb-bee64e2f2d82' "enrollment_autopilot_dpp_deploymentmode_$DeploymentMode")
            (& $Choice 'enrollment_autopilot_dpp_deploymenttype' 'f4184296-fa9f-4b67-8b12-1723b3f8456b' 'e0af022f-37f3-4a40-916d-1ab7281c88d9' "enrollment_autopilot_dpp_deploymenttype_$DeploymentType")
            (& $Choice 'enrollment_autopilot_dpp_jointype' '6310e95d-6cfa-4d2f-aae0-1e7af12e2182' '1fa84eb3-fcfa-4ed6-9687-0f3d486402c4' "enrollment_autopilot_dpp_jointype_$JoinType")
            (& $Choice 'enrollment_autopilot_dpp_accountype' 'd4f2a840-86d5-4162-9a08-fa8cc608b94e' 'bf13bb47-69ef-4e06-97c1-50c2859a49c2' "enrollment_autopilot_dpp_accountype_$AccountType")
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
            (& $Choice 'enrollment_autopilot_dpp_allowskip' '2a71dc89-0f17-4ba9-bb27-af2521d34710' 'a2323e5e-ac56-4517-8847-b0a6fdb467e7' "enrollment_autopilot_dpp_allowskip_$AllowSkip")
            (& $Choice 'enrollment_autopilot_dpp_allowdiagnostics' 'e2b7a81b-f243-4abd-bce3-c1856345f405' 'c59d26fd-3460-4b26-b47a-f7e202e7d5a3' "enrollment_autopilot_dpp_allowdiagnostics_$AllowDiagnostics")
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

    $Body = $PolicyBody | ConvertTo-Json -Compress -Depth 20
    $NewPolicy = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -tenantid $TenantFilter -body $Body -type POST
    if ("$($NewPolicy.id)" -and $AssignmentBody) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($NewPolicy.id)')/assign" -tenantid $TenantFilter -body $AssignmentBody -type POST
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed the Device Prep profile '$ProfileName'." -Sev 'Info'
}
