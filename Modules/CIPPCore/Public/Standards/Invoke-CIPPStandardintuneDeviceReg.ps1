function Invoke-CIPPStandardintuneDeviceReg {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $PreviousSetting = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -tenantid $Tenant
    $StateIsCorrect = if ($PreviousSetting.userDeviceQuota -eq $Settings.max) { $true } else { $false }

    If ($Settings.remediate -eq $true) {

        if ($PreviousSetting.userDeviceQuota -eq $Settings.max) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is already set to $($Settings.max)" -sev Info
        } else {
            try {
                $PreviousSetting.userDeviceQuota = $Settings.max
                $Newbody = ConvertTo-Json -Compress -InputObject $PreviousSetting -Depth 5
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -Type PUT -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set user device quota to $($Settings.max)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set user device quota to $($Settings.max) : $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is set to $($Settings.max)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "User device quota is not set to $($Settings.max)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'intuneDeviceReg' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
