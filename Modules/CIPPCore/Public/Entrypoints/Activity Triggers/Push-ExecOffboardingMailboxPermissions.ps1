function Push-ExecOffboardingMailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param(
        $Item
    )
    $Mailboxes = New-ExoRequest -tenantid $Item.TenantFilter -cmdlet 'get-mailbox' -Select UserPrincipalName
    foreach ($Mailbox in $Mailboxes) {
        Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid $Mailbox.UserPrincipalName -AccessUser $Item.User -TenantFilter $Item.TenantFilter -APIName $APINAME -ExecutingUser $Item.executingUser
    }
}
