function Invoke-CIPPStandardintuneDeviceReg {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate) {
        if ($PreviousSetting.userDeviceQuota -eq $Settings.max) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is already set to $($Settings.max)" -sev Info
        } else {
            try {
                $PreviousSetting.userDeviceQuota = $Settings.max
                $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set user device quota to $($Settings.max)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set user device quota to $($Settings.max) : $($_.exception.message)" -sev Error
            }
        }
    }
    if ($Settings.alert) {

        if ($PreviousSetting.userDeviceQuota -eq $Settings.max) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is set to $($Settings.max)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is not set to $($Settings.max)" -sev Alert
        }
    }
    if ($Settings.report) {
        if ($PreviousSetting.userDeviceQuota -eq $Settings.max) { $UserQuota = $true } else { $UserQuota = $false }
        Add-CIPPBPAField -FieldName 'intuneDeviceReg' -FieldValue [bool]$UserQuota -StoreAs bool -Tenant $tenant
    }
}
