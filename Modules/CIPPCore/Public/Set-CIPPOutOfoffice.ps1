function Set-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $userid,
        $OOO,
        $TenantFilter,
        $ExecutingUser
    )

    try {
        $permissions = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-MailboxAutoReplyConfiguration" -cmdParams @{Identity = $userid; AutoReplyState = "Enabled"; InternalMessage = $OOO; ExternalMessage = $OOO } -Anchor $userid
        Write-LogMessage -user $ExecutingUser -API "Set Out of Office" -message "Set Out-of-office for $($userid)" -Sev "Info" -tenant $TenantFilter
        return "added Out-of-office to $($userid)"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API "Set Out of Office" -message "Could not add OOO for $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not add out of office message for $($userid). Error: $($_.Exception.Message)"
    }
}
