function Remove-CIPPMailboxPermissions {
    [CmdletBinding()]
    param (
        $userid,
        $AccessUser,
        $TenantFilter,
        $PermissionsLevel,

        [Parameter(Mandatory = $false)]
        [switch]$UseCache,

        $APIName = 'Manage Shared Mailbox Access',
        $Headers
    )

    try {
        if ($UseCache.IsPresent) {
            # Use cached permission report to find all mailboxes the user has access to

            Write-Information "Accessing cached mailbox permissions for $AccessUser in tenant $TenantFilter" -InformationAction Continue
            Write-LogMessage -headers $Headers -API $APIName -message "Removing mailbox permissions for $AccessUser using cached permission report" -Sev 'Info' -tenant $TenantFilter

            $UserPermissions = Get-CIPPMailboxPermissionReport -TenantFilter $TenantFilter -ByUser | Where-Object { $_.User -eq $AccessUser }

            if (-not $UserPermissions -or $UserPermissions.Permissions.Count -eq 0) {
                $Message = "No mailbox permissions found for $AccessUser in cached data"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
                return $Message
            }

            $Results = [System.Collections.Generic.List[string]]::new()

            # Loop through each mailbox and remove permissions
            foreach ($PermissionEntry in $UserPermissions.Permissions) {
                $MailboxUPN = $PermissionEntry.MailboxUPN
                $AccessRights = $PermissionEntry.AccessRights -split ', '

                try {
                    # Recursively call this function without UseCache
                    $Result = Remove-CIPPMailboxPermissions -userid $MailboxUPN -AccessUser $AccessUser -TenantFilter $TenantFilter -PermissionsLevel $AccessRights -APIName $APIName -Headers $Headers
                    if ($Result) {
                        $Results.Add($Result)
                    }
                } catch {
                    $ErrorMsg = "Failed to remove permissions from $MailboxUPN for $AccessUser : $($_.Exception.Message)"
                    Write-LogMessage -headers $Headers -API $APIName -message $ErrorMsg -sev 'Warn' -tenant $TenantFilter
                    $Results.Add($ErrorMsg)
                }
            }

            $SummaryMsg = "Processed $($UserPermissions.MailboxCount) mailbox(es) - removed $($Results.Count) permission(s)"
            Write-LogMessage -headers $Headers -API $APIName -message $SummaryMsg -Sev 'Info' -tenant $TenantFilter
            return $Results

        } elseif ($userid -eq 'AllUsers') {
            $Mailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -Select UserPrincipalName
            $Mailboxes | ForEach-Object -Parallel {
                Import-Module '.\Modules\AzBobbyTables'
                Import-Module '.\Modules\CIPPCore'
                Write-Host "Removing permissions from mailbox $($_.UserPrincipalName)"
                Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid $_.UserPrincipalName -AccessUser $using:AccessUser -TenantFilter $using:TenantFilter -APIName $using:APINAME -Headers $using:Headers
            } -ThrottleLimit 10
        } else {
            $Results = $PermissionsLevel | ForEach-Object {
                Write-Information "Removing $($_) permissions for $AccessUser on mailbox $userid" -InformationAction Continue
                switch ($_) {
                    'SendOnBehalf' {
                        $MailboxPerms = New-ExoRequest -Anchor $UserId -tenantid $Tenantfilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $userid; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $AccessUser }; }
                        if ($MailboxPerms -notlike '*completed successfully but no settings of*') {
                            Write-LogMessage -headers $Headers -API $APIName -message "Removed SendOnBehalf permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            # Note: SendOnBehalf not cached as separate permission
                            "Removed SendOnBehalf permissions for $($AccessUser) from $($userid)'s mailbox."
                        }
                    }
                    'SendAS' {
                        $MailboxPerms = New-ExoRequest -Anchor $userId -tenantid $Tenantfilter -cmdlet 'Remove-RecipientPermission' -cmdParams @{Identity = $userid; Trustee = $AccessUser; accessRights = @('SendAs') }

                        # Sync cache regardless of whether permission existed
                        Sync-CIPPMailboxPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $userid -User $AccessUser -PermissionType 'SendAs' -Action 'Remove'

                        if ($MailboxPerms -notlike "*because the ACE isn't present*") {
                            Write-LogMessage -headers $Headers -API $APIName -message "Removed SendAs permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            "Removed SendAs permissions for $($AccessUser) from $($userid)'s mailbox."
                        } else {
                            Write-LogMessage -headers $Headers -API $APIName -message "SendAs permissions for $($AccessUser) on $($userid)'s mailbox were already removed or don't exist." -Sev 'Info' -tenant $TenantFilter
                            "SendAs permissions for $($AccessUser) on $($userid)'s mailbox were already removed or don't exist."
                        }
                    }
                    'FullAccess' {
                        $ExoRequest = @{
                            tenantid  = $TenantFilter
                            cmdlet    = 'Remove-MailboxPermission'
                            cmdParams = @{
                                Identity     = $userid
                                user         = $AccessUser
                                accessRights = @('FullAccess')
                                Verbose      = $true
                            }
                            Anchor    = $userid
                        }
                        $permissions = New-ExoRequest @ExoRequest

                        # Sync cache regardless of whether permission existed
                        Sync-CIPPMailboxPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $userid -User $AccessUser -PermissionType 'FullAccess' -Action 'Remove'

                        if ($permissions -notlike "*because the ACE doesn't exist on the object.*") {
                            Write-LogMessage -headers $Headers -API $APIName -message "Removed FullAccess permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            "Removed FullAccess permissions for $($AccessUser) from $($userid)'s mailbox."
                        } else {
                            Write-LogMessage -headers $Headers -API $APIName -message "FullAccess permissions for $($AccessUser) on $($userid)'s mailbox were already removed or don't exist." -Sev 'Info' -tenant $TenantFilter
                            "FullAccess permissions for $($AccessUser) on $($userid)'s mailbox were already removed or don't exist."
                        }
                    }
                }
            }
        }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not remove mailbox permissions for $($userid). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not remove mailbox permissions for $($userid). Error: $($ErrorMessage.NormalizedError)"
    }
}
