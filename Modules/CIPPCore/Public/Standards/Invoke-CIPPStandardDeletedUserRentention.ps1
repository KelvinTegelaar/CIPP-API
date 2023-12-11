function Invoke-CIPPStandardDeletedUserRentention {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    If ($Settings.remediate) {
        try {
            $body = '{"deletedUserPersonalSiteRetentionPeriodInDays": 365}'
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body $body -ContentType 'application/json'

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set deleted user rentention of OneDrive to 1 year' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set deleted user rentention of OneDrive to 1 year: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {
        if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq 365) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deleted user rentention of OneDrive is set to 1 year' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deleted user rentention of OneDrive is not set to 1 year' -sev Alert
        }
    }
    if ($Settings.report) {
        if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq 365) {
            $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays = $true
        } else {
            $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays = $false
        }
        Add-CIPPBPAField -FieldName 'DeletedUserRentention' -FieldValue [bool]$CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -StoreAs bool -Tenant $tenant
    }
}
