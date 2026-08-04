function Set-CIPPContactPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $APIName = 'Set Contact Permissions',
        $Headers,
        $RemoveAccess,
        $TenantFilter,
        $UserID,
        $FolderName,
        $UserToGetPermissions,
        $LoggingName,
        $Permissions,
        [bool]$SendNotificationToUser = $false
    )

    try {
        # If a pretty logging name is not provided, use the ID instead
        if ([string]::IsNullOrWhiteSpace($LoggingName) -and $RemoveAccess) {
            $LoggingName = $RemoveAccess
        } elseif ([string]::IsNullOrWhiteSpace($LoggingName) -and $UserToGetPermissions) {
            $LoggingName = $UserToGetPermissions
        }

        $FolderIdentity = "$($UserID):\$FolderName"
        $TargetUser = if ($RemoveAccess) { $RemoveAccess } else { $UserToGetPermissions }
        $Resolved = Resolve-CIPPFolderPermissionUser -User $TargetUser -TenantFilter $TenantFilter
        if (-not [string]::IsNullOrWhiteSpace($Resolved.UserEmail) -and [string]::IsNullOrWhiteSpace($LoggingName)) {
            $LoggingName = $Resolved.UserEmail
        } elseif ($Resolved.User -and ($LoggingName -eq $TargetUser)) {
            $LoggingName = $Resolved.User
        }

        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Remove permissions for $LoggingName")) {
                $Attempt = Invoke-CIPPMailboxFolderPermissionAttempt -Action Remove -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID
                $Result = "Successfully removed access for $LoggingName from contact folder $FolderIdentity"
                if ($Attempt.UsedUser -and $Attempt.UsedUser -ne $RemoveAccess) {
                    $Result += " (resolved as $($Attempt.UsedUser))"
                }
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = Invoke-CIPPMailboxFolderPermissionAttempt -Action Set -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID -AccessRights @($Permissions) -SendNotificationToUser $SendNotificationToUser
                } catch {
                    $SetError = Get-CippException -Exception $_
                    if ($SetError.NormalizedError -match 'InvalidExternalUserIdException|Couldn.?t find user|not a valid Exchange recipient|isn.?t a valid user') {
                        throw
                    }
                    $null = Invoke-CIPPMailboxFolderPermissionAttempt -Action Add -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Candidates $Resolved.Candidates -Anchor $UserID -AccessRights @($Permissions) -SendNotificationToUser $SendNotificationToUser
                }

                $Result = "Successfully set permissions on contact folder $FolderIdentity. The user $LoggingName now has $Permissions permissions on this folder."

                if ($SendNotificationToUser) {
                    $Result += ' A notification has been sent to the user.'
                }

                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-Warning "Error changing contact permissions $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        if ($ErrorMessage.NormalizedError -match 'InvalidExternalUserIdException') {
            $Result = "Failed to set contact permissions for $LoggingName on $UserID : The user '$LoggingName' is not a valid Exchange recipient. Ensure they have an Exchange Online mailbox or are a valid mail-enabled object."
        } elseif ($ErrorMessage.NormalizedError -match 'no existing permission entry|UserNotFoundInPermissionEntryException') {
            $Result = "Failed to set contact permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError) If multiple accounts share this display name, remove using the account email, or ensure the mailbox-enabled account is the one granted access."
        } else {
            $Result = "Failed to set contact permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError)"
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }

    return $Result
}
