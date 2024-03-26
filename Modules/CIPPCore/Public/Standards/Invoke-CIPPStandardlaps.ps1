function Invoke-CIPPStandardlaps {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate) {
        if ($PreviousSetting.localadminpassword.isEnabled) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is already enabled.' -sev Info
        } else {
            try {
                $previoussetting.localadminpassword.isEnabled = $true 
                $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS has been enabled.' -sev Info
            } catch {
                $previoussetting.localadminpassword.isEnabled = $false
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set LAPS: $($_.exception.message)" -sev Error
            }
        }
    }
    if ($Settings.alert) {

        if ($PreviousSetting.localadminpassword.isEnabled) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is not enabled.' -sev Alert
        }
    }
    
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'laps' -FieldValue [bool]$PreviousSetting.localadminpassword.isEnabled -StoreAs bool -Tenant $tenant
    }
}
