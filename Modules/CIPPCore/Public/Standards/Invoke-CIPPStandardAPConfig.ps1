function Invoke-CIPPStandardAPConfig {
    <#
    .FUNCTIONALITY
    Internal
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
