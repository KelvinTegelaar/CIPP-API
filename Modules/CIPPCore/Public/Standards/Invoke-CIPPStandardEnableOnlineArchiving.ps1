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
            "Essential 8 (1511)"
            "NIST CSF 2.0 (PR.DS-11)"
        EXECUTIVETEXT
            Automatically enables online email archiving for all licensed employees, providing additional storage for older emails while maintaining easy access. This helps manage mailbox sizes, improves email performance, and supports compliance with data retention requirements.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableOnlineArchiving' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    $MailboxPlans = @( 'ExchangeOnline', 'ExchangeOnlineEnterprise' )
    $MailboxesNoArchive = foreach ($Plan in $MailboxPlans) {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ MailboxPlan = $Plan; Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' }
    }

    if ($Settings.remediate -eq $true) {

        if ($null -eq $MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Online Archiving already enabled for all accounts' -sev Info
        } else {
            try {
                $Request = foreach ($Mailbox in $MailboxesNoArchive) {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Enable-Mailbox'
                            Parameters = @{ Identity = $Mailbox.UserPrincipalName; Archive = $true }
                        }
                    }
                }

                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                foreach ($Result in $BatchResults) {
                    if ($Result.error) {
                        $ErrorMessage = Get-NormalizedError -Message $Result.error
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for $($Result.Target). Error: $ErrorMessage" -sev Error
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
            $Object = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
            Write-StandardsAlert -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -object $Object -tenant $Tenant -standardName 'EnableOnlineArchiving' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
        $stateReport = $filtered ? $filtered : @()

        $CurrentValue = [PSCustomObject]@{
            ArchiveNotEnabled = @($stateReport)
        }
        $ExpectedValue = [PSCustomObject]@{
            ArchiveNotEnabled = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.EnableOnlineArchiving' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $filtered -StoreAs json -Tenant $Tenant
    }
}
