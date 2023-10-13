function Remove-CIPPMailboxPermissions {
    [CmdletBinding()]
    param (
        $userid,
        $AccessUser,
        $TenantFilter,
        $APIName = "Manage Shared Mailbox Access",
        $ExecutingUser
    )

    try {
        $permissions = New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-MailboxPermission" -cmdParams @{Identity = $userid; user = $AccessUser } -Anchor $userid
        Write-LogMessage -user $ExecutingUser -API $APIName -message  "Removed $($AccessUser) from $($userid)'s mailbox." -Sev "Info" -tenant $TenantFilter
        return "Removed $($AccessUser) from $($userid)'s mailbox."
   
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message  "Could not remove mailbox permissions for $($userid). Error: $($_.Exception.Message)" -Sev "Error" -tenant $TenantFilter
        return "Could not remove mailbox permissions for $($userid). Error: $($_.Exception.Message)"
    }
}
