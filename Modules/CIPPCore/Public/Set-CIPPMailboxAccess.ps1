function Set-CIPPMailboxAccess {
    [CmdletBinding()]
    param (
        $userid,
        $AccessUser,
        [bool]$Automap,
        $TenantFilter,
        $APIName = "Manage Shared Mailbox Access",
        $ExecutingUser,
        [array]$AccessRights
    )

    try {
        $permissions = New-ExoRequest -tenantid $TenantFilter -cmdlet "Add-MailboxPermission" -cmdParams @{Identity = $userid; user = $AccessUser; automapping = $Automap; accessRights = $AccessRights; InheritanceType = "all" } -Anchor $userid
        
        if ($Automap) {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Gave $AccessRights permissions to $($AccessUser) on $($userid) with automapping" -Sev "Info" -tenant $TenantFilter
            return "added $($AccessUser) to $($userid) Shared Mailbox with automapping, with the following permissions: $AccessRights"
        } 
        else {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Gave $AccessRights permissions to $($AccessUser) on $($userid) without automapping" -Sev "Info" -tenant $TenantFilter
            return "added $($AccessUser) to $($userid) Shared Mailbox without automapping, with the following permissions: $AccessRights"
        }
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add mailbox permissions for $($AccessUser) on $($userid)" -Sev "Error" -tenant $TenantFilter
        return "Could not add shared mailbox permissions for $($userid). Error: $($_.Exception.Message)"
    }
}
