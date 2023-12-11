function Invoke-CIPPStandardlaps {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate) {
        
        try {
            $previoussetting.localadminpassword.isEnabled = $true 
            $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $newBody -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'LAPS has been enabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set LAPS: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($PreviousSetting.localadminpassword.isEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'LAPS is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'LAPS is not enabled.' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'laps' -FieldValue [bool]$PreviousSetting.localadminpassword.isEnabled -StoreAs bool -Tenant $tenant
    }
}
