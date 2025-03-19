function Push-ExecOffboardingMailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param(
        $Item
    )

    Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid 'AllUsers' -AccessUser $Item.User -TenantFilter $Item.TenantFilter -APIName $Item.APINAME -Headers $Item.Headers
}
