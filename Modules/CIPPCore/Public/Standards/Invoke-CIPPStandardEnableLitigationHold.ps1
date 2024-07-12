function Invoke-CIPPStandardEnableLitigationHold {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableLitigationHold
    .SYNOPSIS
        (Label) Enable Litigation Hold for all users
    .DESCRIPTION
        (Helptext) Enables litigation hold for all UserMailboxes with a valid license.
        (DocsDescription) Enables litigation hold for all UserMailboxes with a valid license.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-Mailbox -LitigationHoldEnabled $true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    
    $MailboxesNoLitHold = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdparams @{ Filter = 'LitigationHoldEnabled -eq "False"'} | Where-Object {$_.PersistedCapabilities -contains "BPOS_S_DlpAddOn" -or $_.PersistedCapabilities -contains "BPOS_S_Enterprise"}
    
    If ($Settings.remediate -eq $true) {

        if ($null -eq $MailboxesNoLitHold) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Litigation Hold already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = $MailboxesNoLitHold | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{ Identity = $_.UserPrincipalName; LitigationHoldEnabled = $true }
                        }
                    }
                }

                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to Enable Litigation Hold for $($_.Target). Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Litigation Hold for $($_.Target). Error: $ErrorMessage" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Litigation Hold for all accounts. Error: $ErrorMessage" -sev Error
            }
        }

    }

    if ($Settings.alert -eq $true) {

        if ($MailboxesNoLitHold) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Litigation Hold: $($MailboxesNoLitHold.Count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Litigation Hold enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNoLitHold | Select-Object -Property UserPrincipalName
        Add-CIPPBPAField -FieldName 'EnableLitHold' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}
