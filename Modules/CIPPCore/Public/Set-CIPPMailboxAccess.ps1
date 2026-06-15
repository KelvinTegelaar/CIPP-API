function Set-CIPPMailboxAccess {
    [CmdletBinding()]
    param (
        $userid,
        [array]$AccessUser, # Can be single value or array of users
        [bool]$Automap,
        $TenantFilter,
        $APIName = 'Manage Shared Mailbox Access',
        $Headers,
        [array]$AccessRights
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

    # Process each access user
    foreach ($User in $AccessUser) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-MailboxPermission' -cmdParams @{Identity = $userid; user = $User; AutoMapping = $Automap; accessRights = $AccessRights; InheritanceType = 'all' } -Anchor $userid

            $Message = "Successfully added $($User) to $($userid) Shared Mailbox $($Automap ? 'with' : 'without') AutoMapping, with the following permissions: $AccessRights"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
            $Results.Add($Message)
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to add mailbox permissions for $($User) on $($userid). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }

    return $Results
}
