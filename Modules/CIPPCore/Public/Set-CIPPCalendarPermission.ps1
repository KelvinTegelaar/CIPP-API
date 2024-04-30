function Set-CIPPCalendarPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $RemoveAccess,
        $TenantFilter,
        $UserID,
        $folderName,
        $UserToGetPermissions,
        $Permissions
    )

    try {
        $CalParam = [PSCustomObject]@{
            Identity     = "$($UserID):\$folderName"
            AccessRights = @($Permissions)
            User         = $UserToGetPermissions
        }
        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Remove permissions for $RemoveAccess")) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{Identity = "$($UserID):\$folderName"; User = $RemoveAccess }
                $Result = "Successfully removed access for $RemoveAccess from calendar $($CalParam.Identity)"
                Write-LogMessage -API 'CalendarPermissions' -tenant $TenantFilter -message "Successfully removed access for $RemoveAccess from calendar $($UserID)" -sev Debug
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Set permissions for $UserToGetPermissions to $Permissions")) {
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                } catch {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                }
                Write-LogMessage -API 'CalendarPermissions' -tenant $TenantFilter -message "Calendar permissions added for $UserToGetPermissions on $UserID." -sev Debug
                $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $UserToGetPermissions now has $Permissions permissions on this folder."
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }

    return $Result
}
