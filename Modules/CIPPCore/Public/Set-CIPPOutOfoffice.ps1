function Set-CIPPOutOfOffice {
    [CmdletBinding()]
    param (
        $userid,
        $OOO,
        $TenantFilter,
        $State,
        $APIName = "Set Out of Office",
        $ExecutingUser
    )

    try {
        if (!$state) { $State = 'Enabled' }
        $OutOfOffice = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-MailboxAutoReplyConfiguration" -cmdParams @{Identity = $userid; AutoReplyState = $State; InternalMessage = $OOO; ExternalMessage = $OOO } -Anchor $userid
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Out-of-office for $($userid) to $state" -Sev "Info" -tenant $TenantFilter
        return "Set Out-of-office for $($userid) to $state"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add OOO for $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not add out of office message for $($userid). Error: $($_.Exception.Message)"
    }
}
