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
        EXECUTIVETEXT
            Preserves all email content for legal and compliance purposes by preventing permanent deletion of emails, even when users attempt to delete them. This is essential for organizations subject to legal discovery requirements or regulatory compliance mandates.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.EnableLitigationHold.days","required":false,"label":"Days to apply for litigation hold"}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-06-25
        POWERSHELLEQUIVALENT
            Set-Mailbox -LitigationHoldEnabled \$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableLitigationHold' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $MailboxesNoLitHold = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ Filter = 'LitigationHoldEnabled -eq "False"' } -Select 'UserPrincipalName,PersistedCapabilities,LitigationHoldEnabled' |
            Where-Object { $_.PersistedCapabilities -contains 'EXCHANGE_S_ARCHIVE_ADDON' -or $_.PersistedCapabilities -contains 'EXCHANGE_S_ENTERPRISE' -or $_.PersistedCapabilities -contains 'BPOS_S_DlpAddOn' -or $_.PersistedCapabilities -contains 'BPOS_S_Enterprise' }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableLitigationHold state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($null -eq $MailboxesNoLitHold) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Litigation Hold already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = foreach ($Mailbox in $MailboxesNoLitHold) {
                    $params = @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{ Identity = $Mailbox.UserPrincipalName; LitigationHoldEnabled = $true }
                        }
                    }
                    if ($null -ne $Settings.days) {
                        $params.CmdletInput.Parameters['LitigationHoldDuration'] = $Settings.days
                    }
                    $params
                }


                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request)
                foreach ($Result in $BatchResults) {
                    if ($Result.error) {
                        $ErrorMessage = Get-NormalizedError -Message $Result.error
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Litigation Hold for $($Result.Target). Error: $ErrorMessage" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Litigation Hold for all accounts. Error: $ErrorMessage" -sev Error
            }
        }

    }

    if ($Settings.alert -eq $true) {
        if (($MailboxesNoLitHold | Measure-Object).Count -gt 0) {
            Write-StandardsAlert -message "Mailboxes without Litigation Hold: $($MailboxesNoLitHold.Count)" -object $MailboxesNoLitHold -tenant $Tenant -standardName 'EnableLitigationHold' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Litigation Hold: $($MailboxesNoLitHold.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Litigation Hold enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNoLitHold | Select-Object -Property UserPrincipalName
        $state = $filtered ? $MailboxesNoLitHold : @()

        $CurrentValue = [PSCustomObject]@{
            EnableLitigationHold = @($state)
        }
        $ExpectedValue = [PSCustomObject]@{
            EnableLitigationHold = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableLitigationHold' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'EnableLitHold' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}
