function Invoke-CIPPStandardDeletedUserRentention {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DeletedUserRentention
    .CAT
    SharePoint Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Sets the retention period for deleted users OneDrive to 1 year/365 days
    .DOCSDESCRIPTION
    When a OneDrive user gets deleted, the personal SharePoint site is saved for 1 year and data can be retrieved from it.
    .ADDEDCOMPONENT
    .LABEL
    Retain a deleted user OneDrive for 1 year
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaAdminSharepointSetting
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the retention period for deleted users OneDrive to 1 year/365 days
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>

    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DeletedUserRentention' -FieldValue $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -StoreAs string -Tenant $tenant
    }

    # Input validation
    if (($Settings.Days -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'DeletedUserRententio: Invalid Days parameter set' -sev Error
        Return
    }

    # Backwards compatibility for pre v5.10.0
    if ($null -eq $Settings.Days) {
        $WantedState = 365
    } else {
        $WantedState = [int]$Settings.Days
    }

    $StateSetCorrectly = if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq $WantedState) { $true } else { $false }
    $RetentionInYears = $WantedState / 365

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateSetCorrectly -eq $false) {
            try {
                $body = [PSCustomObject]@{
                    deletedUserPersonalSiteRetentionPeriodInDays = $Settings.Days
                }
                $body = ConvertTo-Json -InputObject $body -Depth 5 -Compress
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set deleted user rentention of OneDrive to $RetentionInYears year(s)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set deleted user rentention of OneDrive to $RetentionInYears year(s). Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is already set to $RetentionInYears year(s)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateSetCorrectly -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is set to $RetentionInYears year(s)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Deleted user rentention of OneDrive is not set to $RetentionInYears year(s). Value is: $($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays) " -sev Alert
        }
    }
}




