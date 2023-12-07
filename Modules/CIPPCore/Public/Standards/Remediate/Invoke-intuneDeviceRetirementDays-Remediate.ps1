function Invoke-intuneDeviceRetirementDays-Remediate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    try {

        $body = @{ DeviceInactivityBeforeRetirementInDays = $Settings.days } | ConvertTo-Json

    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceCleanupSettings' -Type PATCH -Body $body -ContentType 'application/json')

        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled DeviceInactivityBeforeRetirementInDays.' -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable DeviceInactivityBeforeRetirementInDays. Error: $($_.exception.message)" -sev Error
    }
}
