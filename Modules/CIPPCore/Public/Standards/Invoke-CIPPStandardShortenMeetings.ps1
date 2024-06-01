function Invoke-CIPPStandardShortenMeetings {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    # Input validation
    if ([Int32]$Settings.DefaultMinutesToReduceShortEventsBy -lt 0 -or [Int32]$Settings.DefaultMinutesToReduceShortEventsBy -gt 29) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Invalid shorten meetings settings specified. DefaultMinutesToReduceShortEventsBy must be an integer between 0 and 29' -sev Error
        Exit
    }
    if ([Int32]$Settings.DefaultMinutesToReduceLongEventsBy -lt 0 -or [Int32]$Settings.DefaultMinutesToReduceLongEventsBy -gt 29) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Invalid shorten meetings settings specified. DefaultMinutesToReduceLongEventsBy must be an integer between 0 and 29' -sev Error
        Exit
    }

    $CurrentState = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' | 
        Select-Object -Property ShortenEventScopeDefault, DefaultMinutesToReduceShortEventsBy, DefaultMinutesToReduceLongEventsBy
    $CorrectState = if ($CurrentState.ShortenEventScopeDefault -eq $Settings.ShortenEventScopeDefault -and 
        $CurrentState.DefaultMinutesToReduceShortEventsBy -eq $Settings.DefaultMinutesToReduceShortEventsBy -and 
        $CurrentState.DefaultMinutesToReduceLongEventsBy -eq $Settings.DefaultMinutesToReduceLongEventsBy) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($CorrectState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Shorten meetings settings are already in the correct state. ' -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ShortenEventScopeDefault = $Settings.ShortenEventScopeDefault; DefaultMinutesToReduceShortEventsBy = $Settings.DefaultMinutesToReduceShortEventsBy; DefaultMinutesToReduceLongEventsBy = $Settings.DefaultMinutesToReduceLongEventsBy }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Shorten meetings settings have been set to the following state. State: $($Settings.ShortenEventScopeDefault), Short:$($Settings.DefaultMinutesToReduceShortEventsBy), Long: $($Settings.DefaultMinutesToReduceLongEventsBy)" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set shorten meetings settings. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CorrectState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Shorten meetings settings are already in the correct state. Current state: $($CurrentState.ShortenEventScopeDefault), Short:$($CurrentState.DefaultMinutesToReduceShortEventsBy), Long: $($CurrentState.DefaultMinutesToReduceLongEventsBy)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Shorten meetings settings are not in the correct state. Current state: $($CurrentState.ShortenEventScopeDefault), Short:$($CurrentState.DefaultMinutesToReduceShortEventsBy), Long: $($CurrentState.DefaultMinutesToReduceLongEventsBy)" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {

        if ($CorrectState -eq $true) {
            Add-CIPPBPAField -FieldName 'ShortenMeetings' -FieldValue $CorrectState -StoreAs bool -Tenant $tenant
        } else {
            Add-CIPPBPAField -FieldName 'ShortenMeetings' -FieldValue $CurrentState -StoreAs json -Tenant $tenant
        }
    }
}
