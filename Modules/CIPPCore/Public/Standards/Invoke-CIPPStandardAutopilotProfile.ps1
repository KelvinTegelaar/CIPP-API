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
            
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AutopilotProfile.DisplayName","label":"Profile Display Name"}
            {"type":"textField","name":"standards.AutopilotProfile.Description","label":"Profile Description"}
            {"type":"textField","name":"standards.AutopilotProfile.DeviceNameTemplate","label":"Unique Device Name Template"}
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.AutopilotProfile.Languages","label":"Languages","api":{"url":"/languageList.json","labelField":"language","valueField":"tag"}}
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'APConfig'

    If ($Settings.remediate -eq $true) {

        try {
            Write-Host $($settings | ConvertTo-Json -Depth 100)
            if ($settings.NotLocalAdmin -eq $true) { $usertype = 'Standard' } else { $usertype = 'Administrator' }
            $DeploymentMode = if ($settings.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }

            $Parameters = @{
                tenantFilter       = $tenant
                displayname        = $settings.DisplayName
                description        = $settings.Description
                usertype           = $usertype
                DeploymentMode     = $DeploymentMode
                assignto           = $settings.Assignto
                devicenameTemplate = $Settings.DeviceNameTemplate
                allowWhiteGlove    = $Settings.allowWhiteglove
                CollectHash        = $Settings.CollectHash
                hideChangeAccount  = $Settings.HideChangeAccount
                hidePrivacy        = $Settings.HidePrivacy
                hideTerms          = $Settings.HideTerms
                Autokeyboard       = $Settings.Autokeyboard
                Language           = $Settings.languages.value
            }
            Set-CIPPDefaultAPDeploymentProfile @Parameters
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            # Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create Default Autopilot config: $ErrorMessage" -sev 'Error'
            throw $ErrorMessage
        }

    }
}
