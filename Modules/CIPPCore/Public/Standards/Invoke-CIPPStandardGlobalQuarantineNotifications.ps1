function Invoke-CIPPStandardGlobalQuarantineNotifications {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) GlobalQuarantineNotifications
    .SYNOPSIS
        (Label) Set Global Quarantine Notification Interval
    .DESCRIPTION
        (Helptext) Sets the Global Quarantine Notification Interval to the selected value. Determines how often the quarantine notification is sent to users.
        (DocsDescription) Sets the global quarantine notification interval for the tenant. This is the time between the quarantine notification emails are sent out to users. Default is 24 hours.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.GlobalQuarantineNotifications.NotificationInterval","options":[{"label":"4 hours","value":"04:00:00"},{"label":"1 day/Daily","value":"1.00:00:00"},{"label":"7 days/Weekly","value":"7.00:00:00"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-05-03
        POWERSHELLEQUIVALENT
            Set-QuarantinePolicy -EndUserSpamNotificationFrequency
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'GlobalQuarantineNotifications'

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-QuarantinePolicy' -cmdParams @{ QuarantinePolicyType = 'GlobalQuarantinePolicy' }

    # This might take the cake on ugly hacky stuff i've done,
    # but i just cant understand why the API returns the values it does and not a timespan like the equivalent powershell command does
    # If you know why, please let me know -Bobby
    $CurrentState.EndUserSpamNotificationFrequency = switch ($CurrentState.EndUserSpamNotificationFrequency) {
        'PT4H' { New-TimeSpan -Hours 4 }
        'P1D' { New-TimeSpan -Days 1 }
        'P7D' { New-TimeSpan -Days 7 }
        default { $null }
    }


    # Get notification interval using null-coalescing operator
    $NotificationInterval = $Settings.NotificationInterval.value ?? $Settings.NotificationInterval

    # Input validation
    try {
        $WantedState = [timespan]$NotificationInterval
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "GlobalQuarantineNotifications: Invalid NotificationInterval parameter set. Error: $ErrorMessage" -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CurrentState.EndUserSpamNotificationFrequency -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Global Quarantine Notifications are already set to the desired value of $WantedState" -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-QuarantinePolicy' -cmdParams @{Identity = $CurrentState.Identity; EndUserSpamNotificationFrequency = [string]$WantedState } -useSystemmailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Global Quarantine Notifications to $WantedState" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Global Quarantine Notifications to $WantedState. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentState.EndUserSpamNotificationFrequency -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Global Quarantine Notifications are set to the desired value of $WantedState" -sev Info
        } else {
            $Object = $CurrentState | Select-Object -Property * -ExcludeProperty '*@odata.type'
            Write-StandardsAlert -message "Global Quarantine Notifications are not set to the desired value of $WantedState" -object $Object -tenant $Tenant -standardName 'GlobalQuarantineNotifications' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Global Quarantine Notifications are not set to the desired value of $WantedState" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $notificationInterval = @{ NotificationInterval = "$(($CurrentState.EndUserSpamNotificationFrequency).totalHours) hours" }
        $ReportState = $CurrentState.EndUserSpamNotificationFrequency -eq $WantedState ? $true : $notificationInterval
        Set-CIPPStandardsCompareField -FieldName 'standards.GlobalQuarantineNotifications' -FieldValue $ReportState -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'GlobalQuarantineNotificationsSet' -FieldValue [string]$CurrentState.EndUserSpamNotificationFrequency -StoreAs string -Tenant $Tenant
    }
}
