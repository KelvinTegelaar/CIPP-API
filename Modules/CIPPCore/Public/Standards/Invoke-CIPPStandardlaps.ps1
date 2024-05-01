function Invoke-CIPPStandardlaps {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate!'
        if ($PreviousSetting.localAdminPassword.isEnabled) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is already enabled.' -sev Info
        } else {
            try {
                $PreviousSetting.localAdminPassword.isEnabled = $true
                $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 10
                New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS has been enabled.' -sev Info
            } catch {
                $PreviousSetting.localAdminPassword.isEnabled = $false
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable LAPS: $($_.exception.message)" -sev Error
            }
        }
    }
    if ($Settings.alert -eq $true) {

        if ($PreviousSetting.localAdminPassword.isEnabled) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'LAPS is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'laps' -FieldValue $PreviousSetting.localAdminPassword.isEnabled -StoreAs bool -Tenant $tenant
    }
}
