using namespace System.Net

Function Invoke-ExecOffboard_Mailboxpermissions {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    foreach ($Mailbox in $Mailboxes) {
        Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid $Mailbox.UserPrincipalName -AccessUser $QueueItem.User -TenantFilter $QueueItem.TenantFilter -APIName $APINAME -ExecutingUser $QueueItem.ExecutingUser
    }

}
