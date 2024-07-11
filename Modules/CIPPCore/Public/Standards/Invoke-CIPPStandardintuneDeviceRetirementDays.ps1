function Invoke-CIPPStandardintuneDeviceRetirementDays {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    intuneDeviceRetirementDays
    .CAT
    Intune Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    A value between 0 and 270 is supported. A value of 0 disables retirement, retired devices are removed from Intune after the specified number of days.
    .ADDEDCOMPONENT
    {"type":"number","name":"standards.intuneDeviceRetirementDays.days","label":"Maximum days (0 equals disabled)"}
    .LABEL
    Set inactive device retirement days
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Graph API
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    A value between 0 and 270 is supported. A value of 0 disables retirement, retired devices are removed from Intune after the specified number of days.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $CurrentInfo = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -tenantid $Tenant)
    $StateIsCorrect = if ($PreviousSetting.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) { $true } else { $false }

    If ($Settings.remediate -eq $true) {

        if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DeviceInactivityBeforeRetirementInDays for $($Settings.days) days is already enabled." -sev Info
        } else {
            try {
                $body = @{ DeviceInactivityBeforeRetirementInDays = $Settings.days } | ConvertTo-Json
                (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -Type PATCH -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled DeviceInactivityBeforeRetirementInDays for $($Settings.days) days." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'intuneDeviceRetirementDays' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}




