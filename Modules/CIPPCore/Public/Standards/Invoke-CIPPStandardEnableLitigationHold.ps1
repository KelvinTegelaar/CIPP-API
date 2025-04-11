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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableLitigationHold'

    $MailboxesNoLitHold = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ Filter = 'LitigationHoldEnabled -eq "False"' } -Select 'UserPrincipalName,PersistedCapabilities,LitigationHoldEnabled' | Where-Object { $_.PersistedCapabilities -contains 'BPOS_S_DlpAddOn' -or $_.PersistedCapabilities -contains 'BPOS_S_Enterprise' }

    if ($Settings.remediate -eq $true) {
        if ($null -eq $MailboxesNoLitHold) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Litigation Hold already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = $MailboxesNoLitHold | ForEach-Object {
                    $params = @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{ Identity = $_.UserPrincipalName; LitigationHoldEnabled = $true }
                        }
                    }
                    if ($null -ne $Settings.days) {
                        $params.CmdletInput.Parameters['LitigationHoldDuration'] = $Settings.days
                    }
                    $params
                }


                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to Enable Litigation Hold for $($_.Target). Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Litigation Hold for $($_.Target). Error: $ErrorMessage" -sev Error
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
        $state = $filtered ? $MailboxesNoLitHold : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableLitigationHold' -FieldValue $state -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'EnableLitHold' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}
