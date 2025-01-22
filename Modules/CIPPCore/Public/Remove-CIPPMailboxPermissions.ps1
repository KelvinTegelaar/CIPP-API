function Remove-CIPPMailboxPermissions {
    [CmdletBinding()]
    param (
        $userid,
        $AccessUser,
        $TenantFilter,
        $PermissionsLevel,
        $APIName = 'Manage Shared Mailbox Access',
        $ExecutingUser
    )

    try {
        if ($userid -eq 'AllUsers') {
            $Mailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -Select UserPrincipalName
            $Mailboxes | ForEach-Object -Parallel {
                Import-Module '.\Modules\AzBobbyTables'
                Import-Module '.\Modules\CIPPCore'
                Write-Host "Removing permissions from mailbox $($_.UserPrincipalName)"
                Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid $_.UserPrincipalName -AccessUser $using:AccessUser -TenantFilter $using:TenantFilter -APIName $using:APINAME -ExecutingUser $using:ExecutingUser
            } -ThrottleLimit 10
        } else {
            $Results = $PermissionsLevel | ForEach-Object {
                switch ($_) {
                    'SendOnBehalf' {
                        $MailboxPerms = New-ExoRequest -Anchor $UserId -tenantid $Tenantfilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $userid; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $AccessUser }; }
                        if ($MailboxPerms -notlike '*completed successfully but no settings of*') {
                            Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed SendOnBehalf permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            "Removed SendOnBehalf permissions for $($AccessUser) from $($userid)'s mailbox."
                        }
                    }
                    'SendAS' {
                        $MailboxPerms = New-ExoRequest -Anchor $userId -tenantid $Tenantfilter -cmdlet 'Remove-RecipientPermission' -cmdParams @{Identity = $userid; Trustee = $AccessUser; accessRights = @('SendAs') }
                        if ($MailboxPerms -notlike "*because the ACE isn't present*") {
                            Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed SendAs permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            "Removed SendAs permissions for $($AccessUser) from $($userid)'s mailbox."
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

                        if ($permissions -notlike "*because the ACE doesn't exist on the object.*") {
                            Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed FullAccess permissions for $($AccessUser) from $($userid)'s mailbox." -Sev 'Info' -tenant $TenantFilter
                            "Removed FullAccess permissions for $($AccessUser) from $($userid)'s mailbox."
                        }
                    }
                }
            }
        }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not remove mailbox permissions for $($userid). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not remove mailbox permissions for $($userid). Error: $($ErrorMessage.NormalizedError)"
    }
}
