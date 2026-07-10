function Set-CIPPMailboxAccess {
    [CmdletBinding()]
    param (
        $userid,
        [array]$AccessUser, # Can be single value or array of users
        [bool]$Automap,
        $TenantFilter,
        $APIName = 'Manage Shared Mailbox Access',
        $Headers,
        [array]$AccessRights # Retained for caller compatibility; this helper grants FullAccess
    )

    # Ensure AccessUser is always an array
    if ($AccessUser -isnot [array]) {
        $AccessUser = @($AccessUser)
    }

    # Extract values if objects with .value property (from frontend)
    $AccessUser = $AccessUser | ForEach-Object {
        if ($_ -is [PSCustomObject] -and $_.value) { $_.value } else { $_ }
    }

    $Results = [system.collections.generic.list[string]]::new()

    # Delegate each grant to Set-CIPPMailboxPermission so the permission-level -> EXO cmdlet mapping,
    # logging, cache sync, and error handling all live in one place. This helper grants FullAccess.
    foreach ($User in $AccessUser) {
        $Results.Add(
            (Set-CIPPMailboxPermission -UserId $userid -AccessUser $User -PermissionLevel 'FullAccess' -Action 'Add' -AutoMap $Automap -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers)
        )
    }

    return $Results
}
