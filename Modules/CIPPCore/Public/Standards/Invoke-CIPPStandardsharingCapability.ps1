function Invoke-CIPPStandardsharingCapability {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate) {
        try {
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type patch -Body "{`"sharingCapability`":`"$($Settings.Level)`"}" -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Set sharing level to $($Settings.Level)" -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set sharing level to $($Settings.Level): $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($CurrentInfo.sharingCapability -eq $Settings.level) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Sharing level is set to $($Settings.Level)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Sharing level is not set to $($Settings.Level)" -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'sharingCapability' -FieldValue $CurrentInfo.sharingCapability -StoreAs string -Tenant $tenant
    }
}
