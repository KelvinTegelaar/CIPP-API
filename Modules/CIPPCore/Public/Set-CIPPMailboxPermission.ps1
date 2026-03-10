function Set-CIPPMailboxPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        [string]$AccessUser,

        [Parameter(Mandatory = $true)]
        [ValidateSet('FullAccess', 'SendAs', 'SendOnBehalf', 'ReadPermission',
            'ExternalAccount', 'DeleteItem', 'ChangePermission', 'ChangeOwner')]
        [string]$PermissionLevel,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action,

        [bool]$AutoMap = $true,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$APIName = 'Set Mailbox Permission',

        $Headers,

        [switch]$AsCmdletObject
    )

    $CmdletName = ''
    $CmdletParams = @{}
    $ExpectedResult = ''

    switch ($PermissionLevel) {
        'FullAccess' {
            if ($Action -eq 'Add') {
                $CmdletName = 'Add-MailboxPermission'
                $CmdletParams = @{
                    Identity        = $UserId
                    user            = $AccessUser
                    accessRights    = @('FullAccess')
                    automapping     = $AutoMap
                    InheritanceType = 'all'
                    Confirm         = $false
                }
                $ExpectedResult = "Granted $AccessUser FullAccess to $UserId with automapping $AutoMap"
            } else {
                $CmdletName = 'Remove-MailboxPermission'
                $CmdletParams = @{
                    Identity     = $UserId
                    user         = $AccessUser
                    accessRights = @('FullAccess')
                    Confirm      = $false
                }
                $ExpectedResult = "Removed $AccessUser FullAccess from $UserId"
            }
        }
        'SendAs' {
            if ($Action -eq 'Add') {
                $CmdletName = 'Add-RecipientPermission'
                $CmdletParams = @{
                    Identity     = $UserId
                    Trustee      = $AccessUser
                    accessRights = @('SendAs')
                    Confirm      = $false
                }
                $ExpectedResult = "Granted $AccessUser SendAs permissions to $UserId"
            } else {
                $CmdletName = 'Remove-RecipientPermission'
                $CmdletParams = @{
                    Identity     = $UserId
                    Trustee      = $AccessUser
                    accessRights = @('SendAs')
                    Confirm      = $false
                }
                $ExpectedResult = "Removed $AccessUser SendAs permissions from $UserId"
            }
        }
        'SendOnBehalf' {
            $CmdletName = 'Set-Mailbox'
            if ($Action -eq 'Add') {
                $CmdletParams = @{
                    Identity            = $UserId
                    GrantSendonBehalfTo = @{
                        '@odata.type' = '#Exchange.GenericHashTable'
                        add           = $AccessUser
                    }
                    Confirm             = $false
                }
                $ExpectedResult = "Granted $AccessUser SendOnBehalf permissions to $UserId"
            } else {
                $CmdletParams = @{
                    Identity            = $UserId
                    GrantSendonBehalfTo = @{
                        '@odata.type' = '#Exchange.GenericHashTable'
                        remove        = $AccessUser
                    }
                    Confirm             = $false
                }
                $ExpectedResult = "Removed $AccessUser SendOnBehalf permissions from $UserId"
            }
        }
        default {
            # ReadPermission, ExternalAccount, DeleteItem, ChangePermission, ChangeOwner — Remove only
            if ($Action -eq 'Remove') {
                $CmdletName = 'Remove-MailboxPermission'
                $CmdletParams = @{
                    Identity     = $UserId
                    user         = $AccessUser
                    accessRights = @($PermissionLevel)
                    Confirm      = $false
                }
                $ExpectedResult = "Removed $AccessUser $PermissionLevel from $UserId"
            } else {
                return "Add action is not supported for $PermissionLevel"
            }
        }
    }

    if ($AsCmdletObject) {
        return @{
            CmdletName     = $CmdletName
            Parameters     = $CmdletParams
            ExpectedResult = $ExpectedResult
        }
    }

    # Execute mode
    try {
        $null = New-ExoRequest -Anchor $UserId -tenantid $TenantFilter -cmdlet $CmdletName -cmdParams $CmdletParams
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExpectedResult -Sev 'Info'

        # Sync cache for permission types that have cache entries
        if ($PermissionLevel -in @('FullAccess', 'SendAs', 'SendOnBehalf')) {
            try {
                Sync-CIPPMailboxPermissionCache -TenantFilter $TenantFilter -MailboxIdentity $UserId -User $AccessUser -PermissionType $PermissionLevel -Action $Action
            } catch {
                Write-Information "Cache sync warning: $($_.Exception.Message)"
            }
        }

        return $ExpectedResult
    } catch {
        $ErrorMessage = (Get-CippException -Exception $_).NormalizedError
        $Result = "Failed to $Action $PermissionLevel for $AccessUser on ${UserId}: $ErrorMessage"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        return $Result
    }
}
