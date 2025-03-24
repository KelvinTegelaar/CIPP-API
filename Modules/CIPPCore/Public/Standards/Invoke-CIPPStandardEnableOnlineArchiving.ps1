function Invoke-CIPPStandardEnableOnlineArchiving {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableOnlineArchiving
    .SYNOPSIS
        (Label) Enable Online Archive for all users
    .DESCRIPTION
        (Helptext) Enables the In-Place Online Archive for all UserMailboxes with a valid license.
        (DocsDescription) Enables the In-Place Online Archive for all UserMailboxes with a valid license.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-20
        POWERSHELLEQUIVALENT
            Enable-Mailbox -Archive \$true
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableOnlineArchiving'

    $MailboxPlans = @( 'ExchangeOnline', 'ExchangeOnlineEnterprise' )
    $MailboxesNoArchive = $MailboxPlans | ForEach-Object {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdparams @{ MailboxPlan = $_; Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' }
        Write-Host "Getting mailboxes without Online Archiving for plan $_"
    }

    If ($Settings.remediate -eq $true) {

        if ($null -eq $MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Online Archiving already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = $MailboxesNoArchive | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Enable-Mailbox'
                            Parameters = @{ Identity = $_.UserPrincipalName; Archive = $true }
                        }
                    }
                }

                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to Enable Online Archiving for $($_.Target). Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for $($_.Target). Error: $ErrorMessage" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to Enable Online Archiving for all accounts. Error: $ErrorMessage" -sev Error
            }
        }

    }

    if ($Settings.alert -eq $true) {

        if ($MailboxesNoArchive) {
            Write-StandardsAlert -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -object $MailboxesNoArchive -tenant $Tenant -standardName 'EnableOnlineArchiving' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
        $stateReport = $filtered ? $filtered : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableOnlineArchiving' -FieldValue $stateReport -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}
