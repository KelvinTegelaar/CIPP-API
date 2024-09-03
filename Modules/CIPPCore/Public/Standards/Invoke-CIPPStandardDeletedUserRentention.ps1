function Invoke-CIPPStandardDeletedUserRentention {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DeletedUserRentention
    .SYNOPSIS
        (Label) Set deleted user retention time in OneDrive
    .DESCRIPTION
        (Helptext) Sets the retention period for deleted users OneDrive to the specified period of time. The default is 30 days.
        (DocsDescription) When a OneDrive user gets deleted, the personal SharePoint site is saved for selected amount of time that data can be retrieved from it.
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"Select","name":"standards.DeletedUserRentention.Days","label":"Retention time (Default 30 days)","values":[{"label":"30 days","value":"30"},{"label":"90 days","value":"90"},{"label":"1 year","value":"365"},{"label":"2 years","value":"730"},{"label":"3 years","value":"1095"},{"label":"4 years","value":"1460"},{"label":"5 years","value":"1825"},{"label":"6 years","value":"2190"},{"label":"7 years","value":"2555"},{"label":"8 years","value":"2920"},{"label":"9 years","value":"3285"},{"label":"10 years","value":"3650"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminSharepointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DeletedUserRetention'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DeletedUserRentention' -FieldValue $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -StoreAs string -Tenant $tenant
    }

    # Input validation
    if (($Settings.Days -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeletedUserRententio: Invalid Days parameter set' -sev Error
        Return
    }

    # Backwards compatibility for v5.9.4 and back
    if ($null -eq $Settings.Days) {
        $WantedState = 365
    } else {
        $WantedState = [int]$Settings.Days
    }

    $StateSetCorrectly = if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq $WantedState) { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateSetCorrectly -eq $false) {
            try {
                $body = [PSCustomObject]@{
                    deletedUserPersonalSiteRetentionPeriodInDays = $Settings.Days
                }
                $body = ConvertTo-Json -InputObject $body -Depth 5 -Compress
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set deleted user rentention of OneDrive to $WantedState days(s)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set deleted user rentention of OneDrive to $WantedState days(s). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is already set to $WantedState days(s)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateSetCorrectly -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is set to $WantedState days(s)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is not set to $WantedState days(s). Value is: $($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays) day(s)." -sev Alert
        }
    }
}
