function Invoke-CIPPStandardintuneDeviceRetirementDays {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        
        try {
            $body = @{ DeviceInactivityBeforeRetirementInDays = $Settings.days } | ConvertTo-Json
            (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -Type PATCH -Body $body -ContentType 'application/json')
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DeviceInactivityBeforeRetirementInDays.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $CurrentInfo = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -tenantid $Tenant)
        if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is not enabled.' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($PreviousSetting.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) { $UserQuota = $true } else { $UserQuota = $false }

        Add-CIPPBPAField -FieldName 'intuneDeviceRetirementDays' -FieldValue [bool]$UserQuota -StoreAs bool -Tenant $tenant
    }
}
