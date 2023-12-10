function Invoke-CIPPStandardEnableOnlineArchiving {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $MailboxesNoArchive = (New-ExoRequest -tenantid $tenant -cmdlet 'get-mailbox' -cmdparams @{ Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' })
    If ($Settings.remediate) {
        

        try {
            $MailboxesNoArchive | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet 'enable-Mailbox' -cmdparams @{ Identity = $_.UserPrincipalName; Archive = $true })
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Online Archiving for all accounts' -sev Info
    
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to Enable Online Archiving for all accounts Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($MailboxesNoArchive) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Mailboxes without Online Archiving: $($MailboxesNoArchive.count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All mailboxes have Online Archiving enabled' -sev Info
        }
    }
    if ($Settings.report) {
        $filtered = $MailboxesNoArchive | Select-Object -Property UserPrincipalName, Archive
        Add-CIPPBPAField -FieldName 'EnableOnlineArchiving' -FieldValue $MailboxesNoArchive -StoreAs json -Tenant $tenant
    }
}
