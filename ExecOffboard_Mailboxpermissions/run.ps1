# Input bindings are passed in via param block.
param( $QueueItem, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName

$Mailboxes = New-ExoRequest -tenantid $QueueItem.TenantFilter -cmdlet "get-mailbox"
foreach ($Mailbox in $Mailboxes) {
    Remove-CIPPMailboxPermissions -PermissionsLevel @("FullAccess", "SendAs", "SendOnBehalf") -userid $Mailbox.UserPrincipalName -AccessUser $QueueItem.User -TenantFilter $QueueItem.TenantFilter -APIName $APINAME -ExecutingUser $QueueItem.ExecutingUser
}