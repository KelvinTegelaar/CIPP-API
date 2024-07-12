function Invoke-CIPPStandardFocusedInbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) FocusedInbox
    .SYNOPSIS
        (Label) Set Focused Inbox state
    .DESCRIPTION
        (Helptext) Sets the default Focused Inbox state for the tenant. This can be overridden by the user.
        (DocsDescription) Sets the default Focused Inbox state for the tenant. This can be overridden by the user in their Outlook settings. For more information, see [Microsoft's documentation.](https://support.microsoft.com/en-us/office/focused-inbox-for-outlook-f445ad7f-02f4-4294-a82e-71d8964e3978)
    .NOTES
        CAT
            Exchange Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Select value","name":"standards.FocusedInbox.state","values":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -FocusedInboxOn $true or $false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
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
