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

        $TargetUser = if ($RemoveAccess) { $RemoveAccess } else { $UserToGetPermissions }
        $Resolved = Resolve-CIPPFolderPermissionUser -User $TargetUser -TenantFilter $TenantFilter
        if (-not [string]::IsNullOrWhiteSpace($Resolved.UserEmail) -and [string]::IsNullOrWhiteSpace($LoggingName)) {
            $LoggingName = $Resolved.UserEmail
        } elseif ($Resolved.User -and ($LoggingName -eq $TargetUser)) {
            $LoggingName = $Resolved.User
        }

        $SharingFlags = $null
        if ($CanViewPrivateItems) {
            $SharingFlags = 'Delegate,CanViewPrivateItems'
        }

        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Remove permissions for $LoggingName")) {
                $Attempt = Invoke-CIPPMailboxFolderPermissionAttempt -Action Remove -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID
                $Result = "Successfully removed access for $LoggingName from calendar $($FolderIdentity)"
                if ($Attempt.UsedUser -and $Attempt.UsedUser -ne $RemoveAccess) {
                    $Result += " (resolved as $($Attempt.UsedUser))"
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info

                # Sync cache — use original + resolved identities
                Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $RemoveAccess -Action 'Remove'
                if ($Resolved.UserEmail -and $Resolved.UserEmail -ne $RemoveAccess) {
                    Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $Resolved.UserEmail -Action 'Remove'
                }
                if ($Resolved.User -and $Resolved.User -ne $RemoveAccess) {
                    Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $Resolved.User -Action 'Remove'
                }
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = Invoke-CIPPMailboxFolderPermissionAttempt -Action Set -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID -AccessRights @($Permissions) -SendNotificationToUser $SendNotificationToUser -SharingPermissionFlags $SharingFlags
                } catch {
                    $SetError = Get-CippException -Exception $_
                    # Only fall through to Add when the entry is missing; do not Add after identity resolution failures
                    if ($SetError.NormalizedError -match 'InvalidExternalUserIdException|Couldn.?t find user|not a valid Exchange recipient|isn.?t a valid user') {
                        throw
                    }
                    $null = Invoke-CIPPMailboxFolderPermissionAttempt -Action Add -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID -AccessRights @($Permissions) -SendNotificationToUser $SendNotificationToUser -SharingPermissionFlags $SharingFlags
                }

                $Result = "Successfully set permissions on folder $FolderIdentity. The user $LoggingName now has $Permissions permissions on this folder."
                if ($CanViewPrivateItems) {
                    $Result += ' The user can also view private items.'
                }
                if ($SendNotificationToUser) {
                    $Result += ' A notification has been sent to the user.'
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info

                $CacheUser = $Resolved.UserEmail ?? $UserToGetPermissions
                Sync-CIPPCalendarPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserID -FolderName $FolderName -User $CacheUser -Permissions $Permissions -Action 'Add'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Warning "Error changing calendar permissions $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage

        if ($ErrorMessage.NormalizedError -match 'InvalidExternalUserIdException') {
            $Result = "Failed to set calendar permissions for $LoggingName on $UserID : The user '$LoggingName' is not a valid Exchange recipient. Ensure they have an Exchange Online mailbox or are a valid mail-enabled object."
        } elseif ($ErrorMessage.NormalizedError -match 'no existing permission entry|UserNotFoundInPermissionEntryException') {
            $Result = "Failed to set calendar permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError) If multiple accounts share this display name, remove using the account email, or ensure the mailbox-enabled account is the one granted access."
        } else {
            $Result = "Failed to set calendar permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError)"
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }

    return $Result
}
