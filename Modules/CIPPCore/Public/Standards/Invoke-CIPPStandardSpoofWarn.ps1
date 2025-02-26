function Invoke-CIPPStandardSpoofWarn {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SpoofWarn
    .SYNOPSIS
        (Label) Enable or disable 'external' warning in Outlook
    .DESCRIPTION
        (Helptext) Adds or removes indicators to e-mail messages received from external senders in Outlook. Works on all Outlook clients/OWA
        (DocsDescription) Adds or removes indicators to e-mail messages received from external senders in Outlook. You can read more about this feature on [Microsoft's Exchange Team Blog.](https://techcommunity.microsoft.com/t5/exchange-team-blog/native-external-sender-callouts-on-email-in-outlook/ba-p/2250098)
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"label":"Select value","name":"standards.SpoofWarn.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Set-ExternalInOutlook –Enabled \$true or \$false
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SpoofWarn'

    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ExternalInOutlook')

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SpoofingWarnings' -FieldValue $CurrentInfo.Enabled -StoreAs bool -Tenant $Tenant
    }

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SpoofWarn: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {
        $status = if ($Settings.enable -and $Settings.disable) {
            # Handle pre standards v2.0 legacy settings when this was 2 separate standards
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'You cannot both enable and disable the Spoof Warnings setting' -sev Error
            Return
        } elseif ($state -eq 'enabled' -or $Settings.enable) { $true } else { $false }

        if ($CurrentInfo.Enabled -eq $status) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings are already set to $status." -sev Info
        } else {
            try {
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ Enabled = $status; }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings set to $status." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set Outlook external spoof warnings to $status. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.Enabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outlook external spoof warnings are enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outlook external spoof warnings are not enabled.' -sev Alert
        }
    }
}
