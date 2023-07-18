function Set-CIPPCalenderPermission {
    [CmdletBinding()]
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
            $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-MailboxFolderPermission" -cmdParams @{Identity = "$($UserID):\$folderName"; User = $RemoveAccess }
            Write-LogMessage -API "CalenderPermissions" -tenant $TenantFilter -message "Successfully removed access for $RemoveAccess from calender $($UserID)" -sev Debug
            $Result = "Successfully removed access for $RemoveAccess from calender $($CalParam.Identity)"
        }
        else {
            try {
                $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-MailboxFolderPermission" -cmdParams $CalParam -Anchor $UserID
            }
            catch {
                $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet "Add-MailboxFolderPermission" -cmdParams $CalParam -Anchor $UserID
            }
            Write-LogMessage -API "CalenderPermissions" -tenant $TenantFilter -message "Calendar permissions added for $UserToGetPermissions on $UserID." -sev Debug
            $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $UserToGetPermissions now has $Permissions permissions on this folder."
        }
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }
    
    return $Result
}
