function Invoke-CIPPStandardAutopilotProfile {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutopilotProfile
    .SYNOPSIS
        (Label) Enable Autopilot Profile
    .DESCRIPTION
        (Helptext) Assign the appropriate Autopilot profile to streamline device deployment.
        (DocsDescription) This standard allows the deployment of Autopilot profiles to devices, including settings such as unique name templates, language options, and local admin privileges.
    .NOTES
        CAT
            Device Management Standards
        TAG
            "SMB1001 (2.2)"
        APPLIESTOTEST
            "SMB1001_2_2"
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AutopilotProfile.DisplayName","label":"Profile Display Name"}
            {"type":"textField","name":"standards.AutopilotProfile.Description","label":"Profile Description"}
            {"type":"textField","name":"standards.AutopilotProfile.DeviceNameTemplate","label":"Unique Device Name Template","required":false}
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"name":"standards.AutopilotProfile.Languages","label":"Languages","api":{"url":"/languageList.json","labelField":"languageTag","valueField":"tag"}}
            {"type":"switch","name":"standards.AutopilotProfile.CollectHash","label":"Convert all targeted devices to Autopilot","defaultValue":true}
            {"type":"radio","name":"standards.AutopilotProfile.AssignTo","label":"Assign the profile to","options":[{"label":"Do not assign","value":"none"},{"label":"All devices","value":"allDevices"},{"label":"Custom group(s)","value":"customGroup"}],"defaultValue":"allDevices"}
            {"type":"textField","required":false,"name":"standards.AutopilotProfile.customGroup","label":"Group name(s) to assign","helpText":"Used when 'Custom group(s)' is selected. Wildcards are allowed. Multiple group names are comma-separated."}
            {"type":"textField","required":false,"name":"standards.AutopilotProfile.excludeGroup","label":"Exclude group(s)","helpText":"Group name(s) to exclude from the assignment. Wildcards are allowed. Multiple group names are comma-separated."}
            {"type":"switch","name":"standards.AutopilotProfile.SelfDeployingMode","label":"Enable Self-deploying Mode","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.HideTerms","label":"Hide Terms and Conditions","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.HidePrivacy","label":"Hide Privacy Settings","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.HideChangeAccount","label":"Hide Change Account Options","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.NotLocalAdmin","label":"Setup user as a standard user (not local admin)","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.AllowWhiteGlove","label":"Allow White Glove OOBE","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.AutoKeyboard","label":"Automatically configure keyboard","defaultValue":true}
        IMPACT
            Low Impact
        ADDEDDATE
            2023-12-30
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "INTUNE_A"
            "MDM_Services"
            "EMS"
            "SCCM"
            "MICROSOFTINTUNEPLAN1"
        UPDATECOMMENTBLOCK
            Run the tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutopilotProfile' -TenantFilter $Tenant -Preset Intune

    # Get the current configuration

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Templates saved before the AssignTo radio carry only the AssignToAllDevices switch, which never managed groups.
    $AssignMode = [string]($Settings.AssignTo.value ?? $Settings.AssignTo)
    $LegacyAssign = [string]::IsNullOrWhiteSpace($AssignMode)
    if ($LegacyAssign) {
        $AssignMode = if ($Settings.AssignToAllDevices -eq $true) { 'allDevices' } else { 'none' }
    }
    $IncludeGroupIds = @()
    $ExcludeGroupIds = @()
    $GroupNameById = @{}
    $AssignmentsResolved = $false
    try {
        $CurrentConfig = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $Tenant |
            Where-Object { $_.displayName -eq $Settings.DisplayName } |
            Select-Object -Property id, displayName, description, deviceNameTemplate, locale, preprovisioningAllowed, hardwareHashExtractionEnabled, outOfBoxExperienceSetting

        if ($Settings.NotLocalAdmin -eq $true) { $userType = 'standard' } else { $userType = 'administrator' }
        if ($Settings.SelfDeployingMode -eq $true) {
            $DeploymentMode = 'shared'
            $Settings.AllowWhiteGlove = $false
        } else {
            $DeploymentMode = 'singleUser'
        }

        $IncludeNames = @(if ($AssignMode -eq 'customGroup' -and $Settings.customGroup) { "$($Settings.customGroup)".Split(',').Trim() | Where-Object { $_ } })
        $ExcludeNames = @(if ($AssignMode -ne 'none' -and $Settings.excludeGroup) { "$($Settings.excludeGroup)".Split(',').Trim() | Where-Object { $_ } })
        if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $Tenant
            foreach ($Group in $Groups) { $GroupNameById[$Group.id] = $Group.displayName }
            $IncludeGroupIds = @($Groups | ForEach-Object {
                    foreach ($SingleName in $IncludeNames) {
                        if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                            $_.id
                        }
                    }
                } | Select-Object -Unique)
            $ExcludeGroupIds = @($Groups | ForEach-Object {
                    foreach ($SingleName in $ExcludeNames) {
                        if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                            $_.id
                        }
                    }
                } | Select-Object -Unique)
        }
        if ($AssignMode -eq 'customGroup' -and $IncludeGroupIds.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "No groups found matching '$($Settings.customGroup)' for Autopilot profile '$($Settings.DisplayName)'. Existing assignments are left unchanged." -sev Warning
        }

        $FormatGroups = { param($Ids) @($Ids | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { if ($GroupNameById[$_]) { "$($GroupNameById[$_]) ($_)" } else { $_ } }) }
        $ExpectedAssignments = [PSCustomObject]@{
            allDevices    = $AssignMode -eq 'allDevices'
            includeGroups = @(& $FormatGroups $IncludeGroupIds)
            excludeGroups = @(& $FormatGroups $ExcludeGroupIds)
        }
        $CurrentAssignments = $null
        if ($CurrentConfig) {
            $Assignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$(@($CurrentConfig)[0].id)/assignments" -tenantid $Tenant)
            $CurrentAssignments = [PSCustomObject]@{
                allDevices    = @($Assignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget' }).Count -gt 0
                includeGroups = @(& $FormatGroups ($Assignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' } | ForEach-Object { $_.target.groupId }))
                excludeGroups = @(& $FormatGroups ($Assignments | Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget' } | ForEach-Object { $_.target.groupId }))
            }
        }
        # Legacy settings leave group assignments (and, when off, all assignments) to the tenant.
        if ($LegacyAssign -and $CurrentAssignments) {
            $ExpectedAssignments.includeGroups = $CurrentAssignments.includeGroups
            $ExpectedAssignments.excludeGroups = $CurrentAssignments.excludeGroups
            if ($AssignMode -eq 'none') { $ExpectedAssignments.allDevices = $CurrentAssignments.allDevices }
        }
        $AssignmentsResolved = $true

        $StateIsCorrect = ($CurrentConfig.displayName -eq $Settings.DisplayName) -and
        ($CurrentConfig.description -eq $Settings.Description) -and
        ($CurrentConfig.deviceNameTemplate -eq $Settings.DeviceNameTemplate) -and
        ([string]::IsNullOrWhiteSpace($CurrentConfig.locale) -and [string]::IsNullOrWhiteSpace($Settings.Languages.value) -or $CurrentConfig.locale -eq $Settings.Languages.value) -and
        ($CurrentConfig.preprovisioningAllowed -eq $Settings.AllowWhiteGlove) -and
        ($CurrentConfig.hardwareHashExtractionEnabled -eq $Settings.CollectHash) -and
        ($CurrentConfig.outOfBoxExperienceSetting.deviceUsageType -eq $DeploymentMode) -and
        ($CurrentConfig.outOfBoxExperienceSetting.privacySettingsHidden -eq $Settings.HidePrivacy) -and
        ($CurrentConfig.outOfBoxExperienceSetting.eulaHidden -eq $Settings.HideTerms) -and
        ($DeploymentMode -eq 'shared' -or $CurrentConfig.outOfBoxExperienceSetting.userType -eq $userType) -and
        ($CurrentConfig.outOfBoxExperienceSetting.keyboardSelectionPageSkipped -eq $Settings.AutoKeyboard) -and
        ((ConvertTo-Json -InputObject $CurrentAssignments -Compress) -eq (ConvertTo-Json -InputObject $ExpectedAssignments -Compress))
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to check Autopilot profile: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StateIsCorrect = $false
    }

    $CurrentValue = $CurrentConfig | Select-Object -Property displayName, description, deviceNameTemplate, locale, preprovisioningAllowed, hardwareHashExtractionEnabled, @{Name = 'outOfBoxExperienceSetting'; Expression = {
            $oobe = [PSCustomObject]@{
                deviceUsageType              = $_.outOfBoxExperienceSetting.deviceUsageType
                privacySettingsHidden        = $_.outOfBoxExperienceSetting.privacySettingsHidden
                eulaHidden                   = $_.outOfBoxExperienceSetting.eulaHidden
                keyboardSelectionPageSkipped = $_.outOfBoxExperienceSetting.keyboardSelectionPageSkipped
            }
            if ($DeploymentMode -ne 'shared') {
                $oobe | Add-Member -NotePropertyName 'userType' -NotePropertyValue $_.outOfBoxExperienceSetting.userType
            }
            $oobe
        }
    }, @{Name = 'assignments'; Expression = { $CurrentAssignments } }
    $ExpectedOobe = [PSCustomObject]@{
        deviceUsageType              = $DeploymentMode
        privacySettingsHidden        = $Settings.HidePrivacy
        eulaHidden                   = $Settings.HideTerms
        keyboardSelectionPageSkipped = $Settings.AutoKeyboard
    }
    if ($DeploymentMode -ne 'shared') {
        $ExpectedOobe | Add-Member -NotePropertyName 'userType' -NotePropertyValue $userType
    }
    $ExpectedValue = [PSCustomObject]@{
        displayName                   = $Settings.DisplayName
        description                   = $Settings.Description
        deviceNameTemplate            = $Settings.DeviceNameTemplate
        locale                        = $Settings.Languages.value
        preprovisioningAllowed        = $Settings.AllowWhiteGlove
        hardwareHashExtractionEnabled = $Settings.CollectHash
        outOfBoxExperienceSetting     = $ExpectedOobe
        assignments                   = $ExpectedAssignments
    }

    # Remediate if the state is not correct
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopilot profile '$($Settings.DisplayName)' already exists" -sev Info
        } else {
            try {
                $Parameters = @{
                    TenantFilter       = $Tenant
                    DisplayName        = $Settings.DisplayName
                    Description        = $Settings.Description
                    UserType           = $userType
                    DeploymentMode     = $DeploymentMode
                    AssignTo           = ($AssignMode -eq 'allDevices')
                    GroupIds           = $IncludeGroupIds
                    ExcludeGroupIds    = $ExcludeGroupIds
                    # Only reconcile an explicit mode against a fully read state, and never because a group name matched nothing.
                    Reconcile          = $AssignmentsResolved -and -not $LegacyAssign -and -not ($AssignMode -eq 'customGroup' -and $IncludeGroupIds.Count -eq 0)
                    DeviceNameTemplate = $Settings.DeviceNameTemplate
                    AllowWhiteGlove    = $Settings.AllowWhiteGlove
                    CollectHash        = $Settings.CollectHash
                    HideChangeAccount  = $true
                    HidePrivacy        = $Settings.HidePrivacy
                    HideTerms          = $Settings.HideTerms
                    AutoKeyboard       = $Settings.AutoKeyboard
                    Language           = $Settings.Languages.value
                }

                Set-CIPPDefaultAPDeploymentProfile @Parameters
                if ($null -eq $CurrentConfig) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created Autopilot profile '$($Settings.DisplayName)'" -sev Info
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated Autopilot profile '$($Settings.DisplayName)'" -sev Info
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create Autopilot profile: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                throw $ErrorMessage
            }
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AutopilotProfile' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopilot profile '$($Settings.DisplayName)' exists" -sev Info
        } else {
            Write-StandardsAlert -message "Autopilot profile '$($Settings.DisplayName)' do not match expected configuration" -object $CurrentConfig -tenant $Tenant -standardName 'AutopilotProfile' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopilot profile '$($Settings.DisplayName)' do not match expected configuration" -sev Info
        }
    }
}
