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
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AutopilotProfile.DisplayName","label":"Profile Display Name"}
            {"type":"textField","name":"standards.AutopilotProfile.Description","label":"Profile Description"}
            {"type":"textField","name":"standards.AutopilotProfile.DeviceNameTemplate","label":"Unique Device Name Template","required":false}
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"name":"standards.AutopilotProfile.Languages","label":"Languages","api":{"url":"/languageList.json","labelField":"languageTag","valueField":"tag"}}
            {"type":"switch","name":"standards.AutopilotProfile.CollectHash","label":"Convert all targeted devices to Autopilot","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotProfile.AssignToAllDevices","label":"Assign to all devices","defaultValue":true}
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
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutopilotProfile' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    # Get the current configuration

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    try {
        $CurrentConfig = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' -tenantid $Tenant |
            Where-Object { $_.displayName -eq $Settings.DisplayName } |
            Select-Object -Property displayName, description, deviceNameTemplate, locale, preprovisioningAllowed, hardwareHashExtractionEnabled, outOfBoxExperienceSetting

        if ($Settings.NotLocalAdmin -eq $true) { $userType = 'Standard' } else { $userType = 'Administrator' }
        if ($Settings.SelfDeployingMode -eq $true) {
            $DeploymentMode = 'shared'
            $Settings.AllowWhiteGlove = $false
        } else {
            $DeploymentMode = 'singleUser'
        }

        $StateIsCorrect = ($CurrentConfig.displayName -eq $Settings.DisplayName) -and
        ($CurrentConfig.description -eq $Settings.Description) -and
        ($CurrentConfig.deviceNameTemplate -eq $Settings.DeviceNameTemplate) -and
        ([string]::IsNullOrWhiteSpace($CurrentConfig.locale) -and [string]::IsNullOrWhiteSpace($Settings.Languages.value) -or $CurrentConfig.locale -eq $Settings.Languages.value) -and
        ($CurrentConfig.preprovisioningAllowed -eq $Settings.AllowWhiteGlove) -and
        ($CurrentConfig.hardwareHashExtractionEnabled -eq $Settings.CollectHash) -and
        ($CurrentConfig.outOfBoxExperienceSetting.deviceUsageType -eq $DeploymentMode) -and
        ($CurrentConfig.outOfBoxExperienceSetting.privacySettingsHidden -eq $Settings.HidePrivacy) -and
        ($CurrentConfig.outOfBoxExperienceSetting.eulaHidden -eq $Settings.HideTerms) -and
        ($CurrentConfig.outOfBoxExperienceSetting.userType -eq $userType) -and
        ($CurrentConfig.outOfBoxExperienceSetting.keyboardSelectionPageSkipped -eq $Settings.AutoKeyboard)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to check Autopilot profile: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StateIsCorrect = $false
    }

    # Remediate if the state is not correct
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Autopilot profile '$($Settings.DisplayName)' already exists" -sev Info
        } else {
            try {
                $Parameters = @{
                    tenantFilter       = $Tenant
                    displayName        = $Settings.DisplayName
                    description        = $Settings.Description
                    userType           = $userType
                    DeploymentMode     = $DeploymentMode
                    AssignTo           = $Settings.AssignToAllDevices
                    devicenameTemplate = $Settings.DeviceNameTemplate
                    allowWhiteGlove    = $Settings.AllowWhiteGlove
                    CollectHash        = $Settings.CollectHash
                    hideChangeAccount  = $true
                    hidePrivacy        = $Settings.HidePrivacy
                    hideTerms          = $Settings.HideTerms
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
        $FieldValue = $StateIsCorrect -eq $true ? $true : $CurrentConfig
        Set-CIPPStandardsCompareField -FieldName 'standards.AutopilotProfile' -FieldValue $FieldValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AutopilotProfile' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
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
