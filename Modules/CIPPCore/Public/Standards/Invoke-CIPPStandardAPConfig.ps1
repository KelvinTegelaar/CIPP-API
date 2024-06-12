function Invoke-CIPPStandardAPConfig {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {

        $APINAME = 'Standards'
        try {
            Write-Host $($settings | ConvertTo-Json -Depth 100)
            if ($settings.NotLocalAdmin -eq $true) { $usertype = 'Standard' } else { $usertype = 'Administrator' }
            $DeploymentMode = if ($settings.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }
            Set-CIPPDefaultAPDeploymentProfile -tenantFilter $tenant -displayname $settings.DisplayName -description $settings.Description -usertype $usertype -DeploymentMode $DeploymentMode -assignto $settings.Assignto -devicenameTemplate $Settings.DeviceNameTemplate -allowWhiteGlove $Settings.allowWhiteGlove -CollectHash $Settings.CollectHash -hideChangeAccount $Settings.HideChangeAccount -hidePrivacy $Settings.HidePrivacy -hideTerms $Settings.HideTerms -Autokeyboard $Settings.Autokeyboard -Language $Settings.languages.value
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            #Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create Default Autopilot config: $ErrorMessage" -sev 'Error'
            throw $ErrorMessage
        }

    }
}
