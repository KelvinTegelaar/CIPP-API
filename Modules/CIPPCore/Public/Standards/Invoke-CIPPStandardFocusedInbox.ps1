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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.FocusedInbox.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-04-26
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -FocusedInboxOn \$true or \$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'FocusedInbox'

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    # Input validation
    if ([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ExternalMFATrusted: Invalid state parameter set' -sev Error
        Return
    }

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').FocusedInboxOn

    $WantedState = if ($state -eq 'enabled') { $true } else { $false }
    $StateIsCorrect = if ($CurrentState -eq $WantedState) { $true } else { $false }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is already set to $state." -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ FocusedInboxOn = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set Focused Inbox state to $state." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Focused Inbox state to $state. Error: $($ErrorMessage.NormalizedError)" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is set to $state." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Focused Inbox is not set to $state." -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'FocusedInboxCorrectState' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
