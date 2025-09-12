function Invoke-CIPPStandardDisableResourceMailbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableResourceMailbox
    .SYNOPSIS
        (Label) Disable Unlicensed Resource Mailbox Entra accounts
    .DESCRIPTION
        (Helptext) Blocks login for all accounts that are marked as a resource mailbox and does not have a license assigned. Accounts that are synced from on-premises AD are excluded, as account state is managed in the on-premises AD.
        (DocsDescription) Resource mailboxes can be directly logged into if the password is reset, this presents a security risk as do all shared login credentials. Microsoft's recommendation is to disable the user account for resource mailboxes. Accounts that are synced from on-premises AD are excluded, as account state is managed in the on-premises AD.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-01
        POWERSHELLEQUIVALENT
            Get-Mailbox & Update-MgUser
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DisableResourceMailbox' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableResourceMailbox'

    # Get all users that are able to be
    try {
        $UserList = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999&$filter=accountEnabled eq true and onPremisesSyncEnabled ne true and assignedLicenses/$count eq 0&$count=true' -Tenantid $Tenant -ComplexFilter |
        Where-Object { $_.userType -eq 'Member' }
        $ResourceMailboxList = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ Filter = "RecipientTypeDetails -eq 'RoomMailbox' -or RecipientTypeDetails -eq 'EquipmentMailbox'" } -Select 'UserPrincipalName,DisplayName,RecipientTypeDetails,ExternalDirectoryObjectId' |
        Where-Object { $_.ExternalDirectoryObjectId -in $UserList.id }
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableResourceMailbox state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'


        if ($ResourceMailboxList) {
            Write-Host "Resource Mailboxes to disable: $($ResourceMailboxList.Count)"
            $ResourceMailboxList | ForEach-Object {
                try {
                    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ExternalDirectoryObjectId)" -type PATCH -body '{"accountEnabled":"false"}' -tenantid $Tenant
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Entra account for $($_.RecipientTypeDetails), $($_.DisplayName), $($_.UserPrincipalName) disabled." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Entra account for $($_.RecipientTypeDetails), $($_.DisplayName), $($_.UserPrincipalName). Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for resource mailboxes are already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($ResourceMailboxList) {
            Write-StandardsAlert -message "Resource mailboxes with enabled accounts: $($ResourceMailboxList.Count)" -object $ResourceMailboxList -tenant $Tenant -standardName 'DisableResourceMailbox' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Resource mailboxes with enabled accounts: $($ResourceMailboxList.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for resource mailboxes are disabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        # If there are no resource mailboxes, we set the state to true, so that the standard reports as compliant.
        $State = $ResourceMailboxList ? $ResourceMailboxList : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableResourceMailbox' -FieldValue $State -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'DisableResourceMailbox' -FieldValue $ResourceMailboxList -StoreAs json -Tenant $Tenant
    }
}
