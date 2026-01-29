function Invoke-CIPPStandardAutopilotStatusPage {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AutopilotStatusPage
    .SYNOPSIS
        (Label) Enable Autopilot Status Page
    .DESCRIPTION
        (Helptext) Deploy the Autopilot Status Page, which shows progress during device setup through Autopilot.
        (DocsDescription) This standard allows configuration of the Autopilot Status Page, providing users with a visual representation of the progress during device setup. It includes options like timeout, logging, and retry settings.
    .NOTES
        CAT
            Device Management Standards
        TAG
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        EXECUTIVETEXT
            Provides employees with a visual progress indicator during automated device setup, improving the user experience when receiving new computers. This reduces IT support calls and helps ensure successful device deployment by guiding users through the setup process.
        ADDEDCOMPONENT
            {"type":"number","name":"standards.AutopilotStatusPage.TimeOutInMinutes","label":"Timeout in minutes","defaultValue":60}
            {"type":"textField","name":"standards.AutopilotStatusPage.ErrorMessage","label":"Custom Error Message","required":false}
            {"type":"switch","name":"standards.AutopilotStatusPage.ShowProgress","label":"Show progress to users","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.EnableLog","label":"Turn on log collection","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.OBEEOnly","label":"Show status page only with OOBE setup","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.InstallWindowsUpdates","label":"Install Windows Updates during setup","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.BlockDevice","label":"Block device usage during setup","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.AllowReset","label":"Allow reset","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.AllowFail","label":"Allow users to use device if setup fails","defaultValue":true}
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
    $TestResult = Test-CIPPStandardLicense -StandardName 'AutopilotStatusPage' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    # Get current Autopilot enrollment status page configuration

    if ($TestResult -eq $false) {
        return $true
    } #we're done.
    try {
        $CurrentConfig = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments&orderBy=priority&`$filter=deviceEnrollmentConfigurationType eq 'windows10EnrollmentCompletionPageConfiguration' and priority eq 0" -tenantid $Tenant |
            Select-Object -Property id, displayName, priority, showInstallationProgress, blockDeviceSetupRetryByUser, allowDeviceResetOnInstallFailure, allowLogCollectionOnInstallFailure, customErrorMessage, installProgressTimeoutInMinutes, allowDeviceUseOnInstallFailure, trackInstallProgressForAutopilotOnly, installQualityUpdates

        # Compatibility for standards made in v8.3.0 or before, which did not have the InstallWindowsUpdates setting
        $InstallWindowsUpdates = $Settings.InstallWindowsUpdates ?? $false

        $StateIsCorrect = ($CurrentConfig.installProgressTimeoutInMinutes -eq $Settings.TimeOutInMinutes) -and
        ($CurrentConfig.customErrorMessage -eq $Settings.ErrorMessage) -and
        ($CurrentConfig.showInstallationProgress -eq $Settings.ShowProgress) -and
        ($CurrentConfig.allowLogCollectionOnInstallFailure -eq $Settings.EnableLog) -and
        ($CurrentConfig.trackInstallProgressForAutopilotOnly -eq $Settings.OBEEOnly) -and
        ($CurrentConfig.blockDeviceSetupRetryByUser -eq !$Settings.BlockDevice) -and
        ($CurrentConfig.installQualityUpdates -eq $InstallWindowsUpdates) -and
        ($CurrentConfig.allowDeviceResetOnInstallFailure -eq $Settings.AllowReset) -and
        ($CurrentConfig.allowDeviceUseOnInstallFailure -eq $Settings.AllowFail)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to check Autopilot Enrollment Status Page: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StateIsCorrect = $false
    }

    $CurrentValue = $CurrentConfig | Select-Object -Property id, displayName, priority, showInstallationProgress, blockDeviceSetupRetryByUser, allowDeviceResetOnInstallFailure, allowLogCollectionOnInstallFailure, customErrorMessage, installProgressTimeoutInMinutes, allowDeviceUseOnInstallFailure, trackInstallProgressForAutopilotOnly, installQualityUpdates
    $ExpectedValue = [PSCustomObject]@{
        installProgressTimeoutInMinutes      = $Settings.TimeOutInMinutes
        customErrorMessage                   = $Settings.ErrorMessage
        showInstallationProgress             = $Settings.ShowProgress
        allowLogCollectionOnInstallFailure   = $Settings.EnableLog
        trackInstallProgressForAutopilotOnly = $Settings.OBEEOnly
        blockDeviceSetupRetryByUser          = !$Settings.BlockDevice
        installQualityUpdates                = $InstallWindowsUpdates
        allowDeviceResetOnInstallFailure     = $Settings.AllowReset
        allowDeviceUseOnInstallFailure       = $Settings.AllowFail
    }

    # Remediate if the state is not correct
    if ($Settings.remediate -eq $true) {
        try {
            $Parameters = @{
                TenantFilter          = $Tenant
                ShowProgress          = $Settings.ShowProgress
                BlockDevice           = $Settings.BlockDevice
                InstallWindowsUpdates = $InstallWindowsUpdates
                AllowReset            = $Settings.AllowReset
                EnableLog             = $Settings.EnableLog
                ErrorMessage          = $Settings.ErrorMessage
                TimeOutInMinutes      = $Settings.TimeOutInMinutes
                AllowFail             = $Settings.AllowFail
                OBEEOnly              = $Settings.OBEEOnly
            }

            Set-CIPPDefaultAPEnrollment @Parameters
        } catch {
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AutopilotStatusPage' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AutopilotStatusPage' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $Tenant
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Autopilot Enrollment Status Page is configured correctly' -sev Info
        } else {
            Write-StandardsAlert -message 'Autopilot Enrollment Status Page settings do not match expected configuration' -object $CurrentConfig -tenant $Tenant -standardName 'AutopilotStatusPage' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Autopilot Enrollment Status Page settings do not match expected configuration' -sev Info
        }
    }
}
