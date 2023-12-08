function Invoke-intuneDeviceReg {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        
    try {

        $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
        $PreviousSetting.userDeviceQuota = $Settings.max
        $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
        New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Set user device quota to $($Settings.max)" -sev Info
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set user device quota to $($Settings.max) : $($_.exception.message)" -sev Error
    }
}
}
