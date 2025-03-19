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
    If ($Settings.remediate -eq $true) {
        ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'APESP'
        if ($Rerun -eq $true) {
            exit 0
        }
        try {
            $Parameters = @{
                TenantFilter     = $Tenant
                ShowProgress     = $Settings.ShowProgress
                BlockDevice      = $Settings.blockDevice
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

    # Get current Autopilot enrollment status page configuration
    try {
        $CurrentConfig = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$filter=startswith(displayName,'Windows Autopilot')" -tenantid $Tenant
        
        # Check if the enrollment status page exists
        $ESPConfig = $CurrentConfig.value | Where-Object { $_.displayName -like '*Enrollment Status Page*' }
        
        $ESPConfigured = $null -ne $ESPConfig
        
        # Check if settings match what's expected
        $SettingsMismatch = $false
        $MismatchDetails = @{}
        
        if ($ESPConfigured) {
            # Check timeout setting
            if ($ESPConfig.priority -ne 0) {
                $SettingsMismatch = $true
                $MismatchDetails.Priority = @{Expected = 0; Actual = $ESPConfig.priority }
            }

        }
        
        $StateIsCorrect = $ESPConfigured -and (-not $SettingsMismatch)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to check Autopilot Enrollment Status Page: $ErrorMessage" -sev Error
        $StateIsCorrect = $false
    }
    
    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect -eq $true ? $true : $StateIsCorrect
        Set-CIPPStandardsCompareField -FieldName 'standards.AutopilotStatusPage' -FieldValue $state -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AutopilotStatusPage' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

    if ($Settings.alert) {
        if (!$ESPConfigured) {
            Write-StandardsAlert -message 'Autopilot Enrollment Status Page is not configured' -object @{} -tenant $Tenant -standardName 'AutopilotStatusPage' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Autopilot Enrollment Status Page is not configured' -sev Info
        } elseif ($SettingsMismatch) {
            Write-StandardsAlert -message 'Autopilot Enrollment Status Page settings do not match expected configuration' -object $MismatchDetails -tenant $Tenant -standardName 'AutopilotStatusPage' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Autopilot Enrollment Status Page settings do not match expected configuration' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Autopilot Enrollment Status Page is configured correctly' -sev Info
        }
    }

}
