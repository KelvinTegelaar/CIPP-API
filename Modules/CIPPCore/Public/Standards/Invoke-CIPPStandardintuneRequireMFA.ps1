function Invoke-CIPPStandardintuneRequireMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate) {
        if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Require to use MFA when joining/registering Entra Devices is already enabled.' -sev Info
        } else {
            try {
                $NewSetting = $PreviousSetting
                $NewSetting.multiFactorAuthConfiguration = '1'
                $Newbody = ConvertTo-Json -Compress -InputObject $NewSetting
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set required to use MFA when joining/registering Entra Devices' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set require to use MFA when joining/registering Entra Devices: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Require to use MFA when joining/registering Entra Devices is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Require to use MFA when joining/registering Entra Devices is not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        $RequireMFA = if ($PreviousSetting.multiFactorAuthConfiguration -eq 'required') { $true } else { $false }
        Add-CIPPBPAField -FieldName 'intuneRequireMFA' -FieldValue [bool]$RequireMFA -StoreAs bool -Tenant $tenant
    }
}
