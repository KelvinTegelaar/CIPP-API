function Invoke-CIPPStandardGlobalQuarantineNotifications {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param ($Tenant, $Settings)

    # Exit if invalid state in the frontend is selected
    try {
        $WantedState = [timespan]$Settings.NotificationInterval
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Invalid state selected for Global Quarantine Notifications. Error: $ErrorMessage" -sev Error
        Exit
    }

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-QuarantinePolicy' -cmdParams @{ QuarantinePolicyType = 'GlobalQuarantinePolicy' }

    # This might take the cake on ugly hacky stuff i've done, 
    # but i just cant understand why the API returns the values it does and not a timespan like the equivalent powershell command does
    # If you know why, please let me know -Bobby
    $CurrentState.EndUserSpamNotificationFrequency = switch ($CurrentState.EndUserSpamNotificationFrequency) {
        'PT4H' { New-TimeSpan -Hours 4 }
        'P1D' { New-TimeSpan -Days 1 }
        'P7D' { New-TimeSpan -Days 7 }
        Default { $null }
    }

    if ($Settings.remediate -eq $true) {

        Write-Host 'Time to remediate'
        if ($CurrentState.EndUserSpamNotificationFrequency -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Global Quarantine Notifications are already set to the desired value of $WantedState" -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-QuarantinePolicy' -cmdParams @{Identity = $CurrentState.Identity; EndUserSpamNotificationFrequency = [string]$WantedState } -useSystemmailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set Global Quarantine Notifications to $WantedState" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set Global Quarantine Notifications to $WantedState. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        
        if ($CurrentState.EndUserSpamNotificationFrequency -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Global Quarantine Notifications are set to the desired value of $WantedState" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Global Quarantine Notifications are not set to the desired value of $WantedState" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'GlobalQuarantineNotificationsSet' -FieldValue [string]$CurrentState.EndUserSpamNotificationFrequency -StoreAs string -Tenant $tenant
    }
}