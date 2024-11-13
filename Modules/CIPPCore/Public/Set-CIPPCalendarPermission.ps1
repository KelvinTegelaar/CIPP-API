function Set-CIPPCalendarPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $RemoveAccess,
        $TenantFilter,
        $UserID,
        $folderName,
        $UserToGetPermissions,
        $LoggingName,
        $Permissions
    )

    try {
        # If a pretty logging name is not provided, use the ID instead
        if ([string]::IsNullOrWhiteSpace($LoggingName) -and $RemoveAccess) {
            $LoggingName = $RemoveAccess
        } elseif ([string]::IsNullOrWhiteSpace($LoggingName) -and $UserToGetPermissions) {
            $LoggingName = $UserToGetPermissions
        }

        $CalParam = [PSCustomObject]@{
            Identity     = "$($UserID):\$folderName"
            AccessRights = @($Permissions)
            User         = $UserToGetPermissions
        }
        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Remove permissions for $LoggingName")) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{Identity = "$($UserID):\$folderName"; User = $RemoveAccess }
                $Result = "Successfully removed access for $LoggingName from calendar $($CalParam.Identity)"
                Write-LogMessage -API 'CalendarPermissions' -tenant $TenantFilter -message "Successfully removed access for $LoggingName from calendar $($UserID)" -sev Info
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                } catch {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                }
                Write-LogMessage -API 'CalendarPermissions' -tenant $TenantFilter -message "Calendar permissions added for $LoggingName on $UserID." -sev Info
                $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $LoggingName now has $Permissions permissions on this folder."
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        $Result = $ErrorMessage
    }

    return $Result
}
