function Invoke-CIPPStandardDeletedUserRentention {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $StateSetCorrectly = if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq 365) { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateSetCorrectly -eq $false) {
            try {
                $body = '{"deletedUserPersonalSiteRetentionPeriodInDays": 365}'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Set deleted user rentention of OneDrive to 1 year' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set deleted user rentention of OneDrive to 1 year. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deleted user rentention of OneDrive is already set to 1 year' -sev Info

        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateSetCorrectly) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deleted user rentention of OneDrive is set to 1 year' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Deleted user rentention of OneDrive is not set to 1 year' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'DeletedUserRentention' -FieldValue $StateSetCorrectly -StoreAs bool -Tenant $tenant
    }
}
