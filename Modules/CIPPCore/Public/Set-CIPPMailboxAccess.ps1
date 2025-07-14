function Set-CIPPMailboxAccess {
    [CmdletBinding()]
    param (
        $userid,
        $AccessUser,
        [bool]$Automap,
        $TenantFilter,
        $APIName = 'Manage Shared Mailbox Access',
        $Headers,
        [array]$AccessRights
    )

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxPermission' -cmdParams @{Identity = $userid; user = $AccessUser; AutoMapping = $Automap; accessRights = $AccessRights; InheritanceType = 'all' } -Anchor $userid

        $Message = "Successfully added $($AccessUser) to $($userid) Shared Mailbox $($Automap ? 'with' : 'without') AutoMapping, with the following permissions: $AccessRights"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to add mailbox permissions for $($AccessUser) on $($userid). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
