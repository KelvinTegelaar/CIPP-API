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

    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-ExternalInOutlook')

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state
    $AllowListAdd = $Settings.AllowListAdd.value ?? $Settings.AllowListAdd

    # Test if all entries in the AllowListAdd variable are in the AllowList
    $AllowListCorrect = $true
    $AllowListAddEntries = foreach ($entry in $AllowListAdd) {
        if ($CurrentInfo.AllowList -notcontains $entry) {
            $AllowListCorrect = $false
            Write-Host "AllowList entry $entry not found in current AllowList"
            $entry
        } else {
            Write-Host "AllowList entry $entry found in current AllowList."
        }
    }
    $AllowListAdd = @{'@odata.type' = '#Exchange.GenericHashTable'; Add = $AllowListAddEntries }

    # Debug output
    # Write-Host ($CurrentInfo | ConvertTo-Json -Depth 10)
    # Write-Host ($AllowListAdd | ConvertTo-Json -Depth 10)

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'SpoofWarn: Invalid state parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate!'
        $status = if ($Settings.enable -and $Settings.disable) {
            # Handle pre standards v2.0 legacy settings when this was 2 separate standards
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'You cannot both enable and disable the Spoof Warnings setting' -sev Error
            return
        } elseif ($state -eq 'enabled' -or $Settings.enable) { $true } else { $false }

        try {
            if ($CurrentInfo.Enabled -eq $status -and $AllowListCorrect -eq $true) {
                # Status correct, AllowList correct
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings are already set to $status and the AllowList is correct." -sev Info

            } elseif ($CurrentInfo.Enabled -eq $status -and $AllowListCorrect -eq $false) {
                # Status correct, AllowList incorrect
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ AllowList = $AllowListAdd; }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings already set to $status. Added $($AllowListAdd.Add -join ', ') to the AllowList." -sev Info

            } elseif ($CurrentInfo.Enabled -ne $status -and $AllowListCorrect -eq $false) {
                # Status incorrect, AllowList incorrect
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ Enabled = $status; AllowList = $AllowListAdd; }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings set to $status. Added $($AllowListAdd.Add -join ', ') to the AllowList." -sev Info

            } else {
                # Status incorrect, AllowList correct
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-ExternalInOutlook' -cmdParams @{ Enabled = $status; }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Outlook external spoof warnings set to $status." -sev Info

            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set Outlook external spoof warnings to $status. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.Enabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outlook external spoof warnings are enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Outlook external spoof warnings are not enabled.' -object $CurrentInfo -tenant $Tenant -standardName 'SpoofWarn' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Outlook external spoof warnings are not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SpoofingWarnings' -FieldValue $CurrentInfo.Enabled -StoreAs bool -Tenant $Tenant

        if ($AllowListCorrect -eq $true -and $CurrentInfo.Enabled -eq $status) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentInfo | Select-Object Enabled, AllowList
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SpoofWarn' -FieldValue $FieldValue -Tenant $Tenant
    }
}
