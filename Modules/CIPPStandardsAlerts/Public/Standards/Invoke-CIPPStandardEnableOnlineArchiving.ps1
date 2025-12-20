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
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableOnlineArchiving'

    $MailboxPlans = @( 'ExchangeOnline', 'ExchangeOnlineEnterprise' )
    $MailboxesNoArchive = $MailboxPlans | ForEach-Object {
        New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ MailboxPlan = $_; Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' }
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
            $Object = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, ArchiveGuid
            Write-StandardsAlert -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.Count)" -object $Object -tenant $Tenant -standardName 'EnableOnlineArchiving' -standardId $Settings.standardId
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
