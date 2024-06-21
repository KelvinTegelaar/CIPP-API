function Invoke-CIPPStandardFocusedInbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    # Input validation
    if ([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ExternalMFATrusted: Invalid state parameter set' -sev Error
        Return
    }

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').FocusedInboxOn

    $WantedState = if ($Settings.state -eq 'enabled') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is already set to $($Settings.state)." -sev Info
        } else {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdparams @{ FocusedInboxOn = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Focused Inbox state to $($Settings.state)." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Focused Inbox state to $($Settings.state). Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is set to $($Settings.state)." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is not set to $($Settings.state)." -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'FocusedInboxCorrectState' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
