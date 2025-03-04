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


}
