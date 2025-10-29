function Invoke-CIPPStandardEnrollmentWindowsHelloForBusinessConfiguration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnrollmentWindowsHelloForBusinessConfiguration
    .SYNOPSIS
        (Label) Windows Hello for Business enrollment configuration
    .DESCRIPTION
        (Helptext) Sets the Windows Hello for Business configuration during device enrollment.
        (DocsDescription) Sets the Windows Hello for Business configuration during device enrollment.
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Enables or disables Windows Hello for Business during device enrollment, enhancing security through biometric or PIN-based authentication methods. This ensures that devices meet corporate security standards while providing a user-friendly sign-in experience.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.state","label":"Configure Windows Hello for Business","multiple":false,"options":[{"label":"Not configured","value":"notConfigured"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"switch","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.securityDeviceRequired","label":"Use a Trusted Platform Module (TPM)","default":true}
            {"type":"number","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinMinimumLength","label":"Minimum PIN length (4-127)","default":4}
            {"type":"number","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinMaximumLength","label":"Maximum PIN length (4-127)","default":127}
            {"type":"autoComplete","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinLowercaseCharactersUsage","label":"Lowercase letters in PIN","multiple":false,"options":[{"label":"Not allowed","value":"disallowed"},{"label":"Allowed","value":"allowed"},{"label":"Required","value":"required"}]}
            {"type":"autoComplete","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinUppercaseCharactersUsage","label":"Uppercase letters in PIN","multiple":false,"options":[{"label":"Not allowed","value":"disallowed"},{"label":"Allowed","value":"allowed"},{"label":"Required","value":"required"}]}
            {"type":"autoComplete","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinSpecialCharactersUsage","label":"Special characters in PIN","multiple":false,"options":[{"label":"Not allowed","value":"disallowed"},{"label":"Allowed","value":"allowed"},{"label":"Required","value":"required"}]}
            {"type":"number","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinExpirationInDays","label":"PIN expiration (days) - 0 to disable","default":0}
            {"type":"number","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.pinPreviousBlockCount","label":"PIN history - 0 to disable","default":0}
            {"type":"switch","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.unlockWithBiometricsEnabled","label":"Allow biometric authentication","default":true}
            {"type":"autoComplete","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.enhancedBiometricsState","label":"Use enhanced anti-spoofing when available","multiple":false,"options":[{"label":"Not configured","value":"notConfigured"},{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
            {"type":"switch","name":"standards.EnrollmentWindowsHelloForBusinessConfiguration.remotePassportEnabled","label":"Allow phone sign-in","default":true}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-09-25
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnrollmentWindowsHelloForBusinessConfiguration' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments&orderBy=priority&`$filter=deviceEnrollmentConfigurationType eq 'WindowsHelloForBusiness'" -tenantID $Tenant -AsApp $true |
        Select-Object -Property id, pinMinimumLength, pinMaximumLength, pinUppercaseCharactersUsage, pinLowercaseCharactersUsage, pinSpecialCharactersUsage, state, securityDeviceRequired, unlockWithBiometricsEnabled, remotePassportEnabled, pinPreviousBlockCount, pinExpirationInDays, enhancedBiometricsState
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnrollmentWindowsHelloForBusinessConfiguration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.pinMinimumLength -eq $Settings.pinMinimumLength) -and
    ($CurrentState.pinMaximumLength -eq $Settings.pinMaximumLength) -and
    ($CurrentState.pinUppercaseCharactersUsage -eq $Settings.pinUppercaseCharactersUsage.value) -and
    ($CurrentState.pinLowercaseCharactersUsage -eq $Settings.pinLowercaseCharactersUsage.value) -and
    ($CurrentState.pinSpecialCharactersUsage -eq $Settings.pinSpecialCharactersUsage.value) -and
    ($CurrentState.state -eq $Settings.state.value) -and
    ($CurrentState.securityDeviceRequired -eq $Settings.securityDeviceRequired) -and
    ($CurrentState.unlockWithBiometricsEnabled -eq $Settings.unlockWithBiometricsEnabled) -and
    ($CurrentState.remotePassportEnabled -eq $Settings.remotePassportEnabled) -and
    ($CurrentState.pinPreviousBlockCount -eq $Settings.pinPreviousBlockCount) -and
    ($CurrentState.pinExpirationInDays -eq $Settings.pinExpirationInDays) -and
    ($CurrentState.enhancedBiometricsState -eq $Settings.enhancedBiometricsState.value)

    $CompareField = [PSCustomObject]@{
        pinMinimumLength            = $CurrentState.pinMinimumLength
        pinMaximumLength            = $CurrentState.pinMaximumLength
        pinUppercaseCharactersUsage = $CurrentState.pinUppercaseCharactersUsage
        pinLowercaseCharactersUsage = $CurrentState.pinLowercaseCharactersUsage
        pinSpecialCharactersUsage   = $CurrentState.pinSpecialCharactersUsage
        state                       = $CurrentState.state
        securityDeviceRequired      = $CurrentState.securityDeviceRequired
        unlockWithBiometricsEnabled = $CurrentState.unlockWithBiometricsEnabled
        remotePassportEnabled       = $CurrentState.remotePassportEnabled
        pinPreviousBlockCount       = $CurrentState.pinPreviousBlockCount
        pinExpirationInDays         = $CurrentState.pinExpirationInDays
        enhancedBiometricsState     = $CurrentState.enhancedBiometricsState
    }

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'EnrollmentWindowsHelloForBusinessConfiguration is already applied correctly.' -Sev Info
        }
        else {
            $cmdParam = @{
                tenantid    = $Tenant
                uri         = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($CurrentState.id)"
                AsApp       = $false
                Type        = 'PATCH'
                ContentType = 'application/json; charset=utf-8'
                Body        = [PSCustomObject]@{
                    "@odata.type"             = "#microsoft.graph.deviceEnrollmentWindowsHelloForBusinessConfiguration"
                    pinMinimumLength          = $Settings.pinMinimumLength
                    pinMaximumLength          = $Settings.pinMaximumLength
                    pinUppercaseCharactersUsage = $Settings.pinUppercaseCharactersUsage.value
                    pinLowercaseCharactersUsage = $Settings.pinLowercaseCharactersUsage.value
                    pinSpecialCharactersUsage   = $Settings.pinSpecialCharactersUsage.value
                    state                       = $Settings.state.value
                    securityDeviceRequired      = $Settings.securityDeviceRequired
                    unlockWithBiometricsEnabled = $Settings.unlockWithBiometricsEnabled
                    remotePassportEnabled       = $Settings.remotePassportEnabled
                    pinPreviousBlockCount       = $Settings.pinPreviousBlockCount
                    pinExpirationInDays         = $Settings.pinExpirationInDays
                    enhancedBiometricsState     = $Settings.enhancedBiometricsState.value
                } | ConvertTo-Json -Compress -Depth 10
            }
            try {
                $null = New-GraphPostRequest @cmdParam
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully updated EnrollmentWindowsHelloForBusinessConfiguration.' -Sev Info
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to update EnrollmentWindowsHelloForBusinessConfiguration. Error: $($ErrorMessage.NormalizedError)" -Sev Error
            }
        }

    }

    If ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'EnrollmentWindowsHelloForBusinessConfiguration is correctly set.' -Sev Info
        }
        else {
            Write-StandardsAlert -message 'EnrollmentWindowsHelloForBusinessConfiguration is incorrectly set.' -object $CompareField -tenant $Tenant -standardName 'EnrollmentWindowsHelloForBusinessConfiguration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'EnrollmentWindowsHelloForBusinessConfiguration is incorrectly set.' -Sev Info
        }
    }

    If ($Settings.report -eq $true) {
        $FieldValue = $StateIsCorrect ? $true : $CompareField
        Set-CIPPStandardsCompareField -FieldName 'standards.EnrollmentWindowsHelloForBusinessConfiguration' -FieldValue $FieldValue -TenantFilter $Tenant
    }
}
