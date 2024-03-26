function Invoke-CIPPStandardintuneDeviceRetirementDays {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -tenantid $Tenant)
    
    If ($Settings.remediate) {
        
        if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "DeviceInactivityBeforeRetirementInDays for $($Settings.days) days is already enabled." -sev Info
        } else {
            try {
                $body = @{ DeviceInactivityBeforeRetirementInDays = $Settings.days } | ConvertTo-Json
                (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -Type PATCH -Body $body -ContentType 'application/json')
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Enabled DeviceInactivityBeforeRetirementInDays for $($Settings.days) days." -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($CurrentInfo.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeviceInactivityBeforeRetirementInDays is not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        $UserQuota = if ($PreviousSetting.DeviceInactivityBeforeRetirementInDays -eq $Settings.days) { $true } else { $false }

        Add-CIPPBPAField -FieldName 'intuneDeviceRetirementDays' -FieldValue [bool]$UserQuota -StoreAs bool -Tenant $tenant
    }
}
