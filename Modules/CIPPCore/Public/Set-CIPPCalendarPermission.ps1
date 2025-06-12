function Set-CIPPCalendarPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $APIName = 'Set Calendar Permissions',
        $Headers,
        $RemoveAccess,
        $TenantFilter,
        $UserID,
        $folderName,
        $UserToGetPermissions,
        $LoggingName,
        $Permissions,
        [bool]$CanViewPrivateItems
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

        if ($CanViewPrivateItems) {
            $CalParam | Add-Member -NotePropertyName 'SharingPermissionFlags' -NotePropertyValue 'Delegate,CanViewPrivateItems'
        }
        
        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Remove permissions for $LoggingName")) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{Identity = "$($UserID):\$folderName"; User = $RemoveAccess }
                $Result = "Successfully removed access for $LoggingName from calendar $($CalParam.Identity)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$folderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                } catch {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully set Calendar permissions $Permissions for $LoggingName on $UserID." -sev Info
                $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $LoggingName now has $Permissions permissions on this folder."
                if ($CanViewPrivateItems) {
                    $Result += " The user can also view private items."
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Warning "Error changing calendar permissions $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        $Result = "Failed to set calendar permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }

    return $Result
}
