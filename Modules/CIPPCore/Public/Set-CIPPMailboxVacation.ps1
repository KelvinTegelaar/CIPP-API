function Set-CIPPMailboxVacation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Add', 'Remove')]
        [string]$Action,

        [object[]]$MailboxPermissions,

        [object[]]$CalendarPermissions,

        [string]$APIName = 'Mailbox Vacation Mode',

        $Headers
    )

    $Results = [System.Collections.Generic.List[string]]::new()

    # Normalize single-element arrays (JSON deserialization quirk)
    $MailboxPermissions = @($MailboxPermissions)
    $CalendarPermissions = @($CalendarPermissions)

    # Process mailbox permissions
    foreach ($perm in $MailboxPermissions) {
        if ($null -eq $perm) { continue }

        # Handle both hashtable and PSCustomObject property access
        $permUserId = $perm.UserId ?? $perm['UserId']
        $permAccessUser = $perm.AccessUser ?? $perm['AccessUser']
        $permLevel = $perm.PermissionLevel ?? $perm['PermissionLevel']
        $permAutoMap = $perm.AutoMap ?? $perm['AutoMap'] ?? $true

        if (-not $permUserId -or -not $permAccessUser -or -not $permLevel) {
            $Results.Add('Skipped mailbox permission with missing fields')
            continue
        }

        $PermSplat = @{
            UserId          = $permUserId
            AccessUser      = $permAccessUser
            PermissionLevel = $permLevel
            Action          = $Action
            AutoMap         = [bool]$permAutoMap
            TenantFilter    = $TenantFilter
            APIName         = $APIName
            Headers         = $Headers
        }
        $result = Set-CIPPMailboxPermission @PermSplat

        $Results.Add($result)
    }

    # Process calendar permissions
    foreach ($calPerm in $CalendarPermissions) {
        if ($null -eq $calPerm) { continue }

        $calUserId = $calPerm.UserID ?? $calPerm['UserID']
        $calDelegate = $calPerm.UserToGetPermissions ?? $calPerm['UserToGetPermissions']
        $calFolder = $calPerm.FolderName ?? $calPerm['FolderName'] ?? 'Calendar'
        $calPermissions = $calPerm.Permissions ?? $calPerm['Permissions']
        $calPrivateItems = $calPerm.CanViewPrivateItems ?? $calPerm['CanViewPrivateItems'] ?? $false

        if (-not $calUserId -or -not $calDelegate) {
            $Results.Add('Skipped calendar permission with missing fields')
            continue
        }

        try {
            $CalSplat = @{
                TenantFilter = $TenantFilter
                UserID       = $calUserId
                FolderName   = $calFolder
                APIName      = $APIName
                Headers      = $Headers
            }
            if ($Action -eq 'Remove') {
                $CalSplat.RemoveAccess = $calDelegate
            } else {
                $CalSplat.UserToGetPermissions = $calDelegate
                $CalSplat.Permissions = $calPermissions
                $CalSplat.CanViewPrivateItems = [bool]$calPrivateItems
            }
            $result = Set-CIPPCalendarPermission @CalSplat
            $Results.Add($result)
        } catch {
            $ErrorMessage = (Get-CippException -Exception $_).NormalizedError
            $Results.Add("Failed calendar permission for $calDelegate on ${calUserId}: $ErrorMessage")
        }
    }

    return $Results
}
