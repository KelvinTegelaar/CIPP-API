function Set-CIPPCalendarPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $APIName = 'Set Calendar Permissions',
        $Headers,
        $RemoveAccess,
        $TenantFilter,
        $UserID,
        $FolderName,
        $UserToGetPermissions,
        $LoggingName,
        $Permissions,
        [bool]$CanViewPrivateItems,
        [bool]$SendNotificationToUser = $false,
        [switch]$AutoResolveFolderName
    )

    try {
        # If a pretty logging name is not provided, use the ID instead
        if ([string]::IsNullOrWhiteSpace($LoggingName) -and $RemoveAccess) {
            $LoggingName = $RemoveAccess
        } elseif ([string]::IsNullOrWhiteSpace($LoggingName) -and $UserToGetPermissions) {
            $LoggingName = $UserToGetPermissions
        }

        # When -AutoResolveFolderName is set, look up the locale-independent FolderId.
        # FolderType -eq 'Calendar' is an internal Exchange enum, always English regardless of mailbox language.
        # Callers that already supply the correct localized FolderName should NOT pass this switch.
        if ($AutoResolveFolderName) {
            $CalFolderStats = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -cmdParams @{
                Identity    = $UserID
                FolderScope = 'Calendar'
            } -Anchor $UserID | Where-Object { $_.FolderType -eq 'Calendar' }
            $FolderIdentity = if ($CalFolderStats) { "$($UserID):$($CalFolderStats.FolderId)" } else { "$($UserID):\$FolderName" }
        } else {
            $FolderIdentity = "$($UserID):\$FolderName"
        }

        $CalParam = [PSCustomObject]@{
            Identity               = $FolderIdentity
            AccessRights           = @($Permissions)
            User                   = $UserToGetPermissions
            SendNotificationToUser = $SendNotificationToUser
        }

        if ($CanViewPrivateItems) {
            $CalParam | Add-Member -NotePropertyName 'SharingPermissionFlags' -NotePropertyValue 'Delegate,CanViewPrivateItems'
        }

        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Remove permissions for $LoggingName")) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MailboxFolderPermission' -cmdParams @{Identity = $FolderIdentity; User = $RemoveAccess }
                $Result = "Successfully removed access for $LoggingName from calendar $($CalParam.Identity)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info

                # Sync cache
                Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $RemoveAccess -Action 'Remove'
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                } catch {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $CalParam -Anchor $UserID
                }
                $Result = "Successfully set permissions on folder $($CalParam.Identity). The user $LoggingName now has $Permissions permissions on this folder."
                if ($CanViewPrivateItems) {
                    $Result += ' The user can also view private items.'
                }
                if ($SendNotificationToUser) {
                    $Result += ' A notification has been sent to the user.'
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info

                # Sync cache
                Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $UserToGetPermissions -Permissions $Permissions -Action 'Add'
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
