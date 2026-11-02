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

        $ContactParam = [PSCustomObject]@{
            Identity               = "$($UserID):\$FolderName"
            AccessRights           = @($Permissions)
            User                   = $UserToGetPermissions
            SendNotificationToUser = $SendNotificationToUser
        }

        if ($RemoveAccess) {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Remove permissions for $LoggingName")) {
                $null = Remove-CIPPFolderPermission -TenantFilter $TenantFilter -FolderIdentity "$($UserID):\$FolderName" -User $RemoveAccess -AccessRights ($Permissions -join ', ') -Anchor $UserID
                $Result = "Successfully removed access for $LoggingName from contact folder $($ContactParam.Identity)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            }
        } else {
            if ($PSCmdlet.ShouldProcess("$UserID\$FolderName", "Set permissions for $LoggingName to $Permissions")) {
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-MailboxFolderPermission' -cmdParams $ContactParam -Anchor $UserID
                } catch {
                    # Set fails when there is no entry to update, so Add is the expected fallback.
                    # Keep Set's error too, or an unrelated Add failure hides why Set failed.
                    $SetError = $_
                    try {
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxFolderPermission' -cmdParams $ContactParam -Anchor $UserID
                    } catch {
                        throw "Set-MailboxFolderPermission failed ($($SetError.Exception.Message)) and Add-MailboxFolderPermission also failed: $($_.Exception.Message)"
                    }
                }

                $Result = "Successfully set permissions on contact folder $($ContactParam.Identity). The user $LoggingName now has $Permissions permissions on this folder."

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
        $Result = "Failed to set contact permissions for $LoggingName on $UserID : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }

    return $Result
}
