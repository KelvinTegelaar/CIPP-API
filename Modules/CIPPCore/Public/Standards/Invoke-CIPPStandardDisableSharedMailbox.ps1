function Invoke-CIPPStandardDisableSharedMailbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableSharedMailbox
    .SYNOPSIS
        (Label) Disable Shared Mailbox Entra accounts
    .DESCRIPTION
        (Helptext) Blocks login for all accounts that are marked as a shared mailbox. This is Microsoft best practice to prevent direct logons to shared mailboxes.
        (DocsDescription) Shared mailboxes can be directly logged into if the password is reset, this presents a security risk as do all shared login credentials. Microsoft's recommendation is to disable the user account for shared mailboxes. It would be a good idea to review the sign-in reports to establish potential impact.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "CIS M365 5.0 (1.2.2)"
            "CISA (MS.AAD.10.1v1)"
            "NIST CSF 2.0 (PR.AA-01)"
        EXECUTIVETEXT
            Prevents direct login to shared mailbox accounts (like info@company.com), ensuring they can only be accessed through authorized users' accounts. This security measure eliminates the risk of shared passwords and unauthorized access while maintaining proper access control and audit trails.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2021-11-16
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
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableSharedMailbox'

    try {
        $UserList = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999&$filter=accountEnabled eq true and onPremisesSyncEnabled ne true&$count=true' -Tenantid $Tenant -ComplexFilter
        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($Tenant)/Mailbox" -Tenantid $Tenant -scope ExchangeOnline | Where-Object { $_.RecipientTypeDetails -EQ 'SharedMailbox' -or $_.RecipientTypeDetails -eq 'SchedulingMailbox' -and $_.UserPrincipalName -in $UserList.UserPrincipalName })
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableSharedMailbox state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    If ($Settings.remediate -eq $true) {

        if ($SharedMailboxList) {
            $SharedMailboxList | ForEach-Object {
                try {
                    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type PATCH -body '{"accountEnabled":"false"}' -tenantid $Tenant
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Entra account for shared mailbox $($_.DisplayName) disabled." -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Entra account for shared mailbox. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for shared mailboxes are already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($SharedMailboxList) {
            Write-StandardsAlert -message "Shared mailboxes with enabled accounts: $($SharedMailboxList.Count)" -object $SharedMailboxList -tenant $Tenant -standardName 'DisableSharedMailbox' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Shared mailboxes with enabled accounts: $($SharedMailboxList.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All Entra accounts for shared mailboxes are disabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $State = $SharedMailboxList ? $SharedMailboxList : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableSharedMailbox' -FieldValue $State -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'DisableSharedMailbox' -FieldValue $SharedMailboxList -StoreAs json -Tenant $Tenant
    }
}
