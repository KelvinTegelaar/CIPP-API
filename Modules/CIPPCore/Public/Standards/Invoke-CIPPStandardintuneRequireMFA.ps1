function Invoke-intuneRequireMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.Remediate) {
        try {
            $PreviousSetting.multiFactorAuthConfiguration = '1'
            $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set required to use MFA when joining Intune Devices' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set require to use MFA when joining Intune Devices: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.Alert) {
        if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Require to use MFA when joining Intune Devices is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Require to use MFA when joining Intune Devices is not enabled.' -sev Alert
        }
    }
}
