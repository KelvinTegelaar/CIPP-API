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
        ADDEDCOMPONENT
            {"type":"number","name":"standards.AutopilotStatusPage.TimeOutInMinutes","label":"Timeout in minutes","defaultValue":60}
            {"type":"textField","name":"standards.AutopilotStatusPage.ErrorMessage","label":"Custom Error Message","required":false}
            {"type":"switch","name":"standards.AutopilotStatusPage.ShowProgress","label":"Show progress to users","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.EnableLog","label":"Turn on log collection","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.OBEEOnly","label":"Show status page only with OOBE setup","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.BlockDevice","label":"Block device usage during setup","defaultValue":true}
            {"type":"switch","name":"standards.AutopilotStatusPage.AllowRetry","label":"Allow retry","defaultValue":true}
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/
    #>
    param($Tenant, $Settings)

    # Get current Autopilot enrollment status page configuration
    try {
        $CurrentConfig = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments&orderBy=priority&`$filter=deviceEnrollmentConfigurationType eq 'windows10EnrollmentCompletionPageConfiguration' and priority eq 0" -tenantid $Tenant |
        Select-Object -Property id, displayName, priority, showInstallationProgress, blockDeviceSetupRetryByUser, allowDeviceResetOnInstallFailure, allowLogCollectionOnInstallFailure, customErrorMessage, installProgressTimeoutInMinutes, allowDeviceUseOnInstallFailure, trackInstallProgressForAutopilotOnly

        $StateIsCorrect = ($CurrentConfig.installProgressTimeoutInMinutes -eq $Settings.TimeOutInMinutes) -and
            ($CurrentConfig.customErrorMessage -eq $Settings.ErrorMessage) -and
            ($CurrentConfig.showInstallationProgress -eq $Settings.ShowProgress) -and
            ($CurrentConfig.allowLogCollectionOnInstallFailure -eq $Settings.EnableLog) -and
            ($CurrentConfig.trackInstallProgressForAutopilotOnly -eq $Settings.OBEEOnly) -and
            ($CurrentConfig.blockDeviceSetupRetryByUser -eq !$Settings.BlockDevice) -and
            ($CurrentConfig.allowDeviceResetOnInstallFailure -eq $Settings.AllowReset) -and
            ($CurrentConfig.allowDeviceUseOnInstallFailure -eq $Settings.AllowFail)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to check Autopilot Enrollment Status Page: $ErrorMessage" -sev Error
        $StateIsCorrect = $false
    }

    # Remediate if the state is not correct
    If ($Settings.remediate -eq $true) {
        try {
            $Parameters = @{
                TenantFilter     = $Tenant
                ShowProgress     = $Settings.ShowProgress
                BlockDevice      = $Settings.BlockDevice
                AllowReset       = $Settings.AllowReset
                EnableLog        = $Settings.EnableLog
                ErrorMessage     = $Settings.ErrorMessage
                TimeOutInMinutes = $Settings.TimeOutInMinutes
                AllowFail        = $Settings.AllowFail
                OBEEOnly         = $Settings.OBEEOnly
            }

            Set-CIPPDefaultAPEnrollment @Parameters
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            throw $ErrorMessage
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        $FieldValue = $StateIsCorrect -eq $true ? $true : $CurrentConfig
        Set-CIPPStandardsCompareField -FieldName 'standards.AutopilotStatusPage' -FieldValue $FieldValue -TenantFilter $Tenant
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
