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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"name":"standards.DeletedUserRentention.Days","label":"Retention time (Default 30 days)","options":[{"label":"30 days","value":"30"},{"label":"90 days","value":"90"},{"label":"1 year","value":"365"},{"label":"2 years","value":"730"},{"label":"3 years","value":"1095"},{"label":"4 years","value":"1460"},{"label":"5 years","value":"1825"},{"label":"6 years","value":"2190"},{"label":"7 years","value":"2555"},{"label":"8 years","value":"2920"},{"label":"9 years","value":"3285"},{"label":"10 years","value":"3650"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-06-15
        POWERSHELLEQUIVALENT
            Update-MgBetaAdminSharePointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DeletedUserRetention'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    $Days = $Settings.Days.value ?? $Settings.Days

    if ($Settings.report -eq $true) {
        $CurrentState = $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq $Days ? $true : ($CurrentInfo | Select-Object deletedUserPersonalSiteRetentionPeriodInDays)
        Set-CIPPStandardsCompareField -FieldName 'standards.DeletedUserRentention' -FieldValue $CurrentState -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DeletedUserRentention' -FieldValue $CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -StoreAs string -Tenant $Tenant
    }

    # Get days value using null-coalescing operator

    # Input validation
    if (($Days -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'DeletedUserRentention: Invalid Days parameter set' -sev Error
        Return
    }

    # Backwards compatibility for v5.9.4 and back
    if ([string]::IsNullOrWhiteSpace($Days)) {
        $WantedState = 365
    } else {
        $WantedState = [int]$Days
    }

    $StateSetCorrectly = if ($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays -eq $WantedState) { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateSetCorrectly -eq $false) {
            try {
                $body = [PSCustomObject]@{
                    deletedUserPersonalSiteRetentionPeriodInDays = $Days
                }
                $body = ConvertTo-Json -InputObject $body -Depth 5 -Compress
                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -AsApp $true -Type PATCH -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set deleted user retention of OneDrive to $WantedState day(s)" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set deleted user retention of OneDrive to $WantedState day(s). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Deleted user retention of OneDrive is already set to $WantedState day(s)" -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateSetCorrectly -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Deleted user retention of OneDrive is set to $WantedState day(s)" -sev Info
        } else {
            Write-StandardsAlert -message "Deleted user retention of OneDrive is not set to $WantedState day(s)." -object $CurrentInfo -tenant $Tenant -standardName 'DeletedUserRentention' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Deleted user retention of OneDrive is not set to $WantedState day(s). Current value is: $($CurrentInfo.deletedUserPersonalSiteRetentionPeriodInDays) day(s)." -sev Info
        }
    }
}
