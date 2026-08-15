function Get-CIPPBaselineDisableResourceMailboxState {
    <#
    .SYNOPSIS
        Prepare hook for DisableResourceMailbox: room and equipment mailboxes whose Entra
        account is still enabled.
    .DESCRIPTION
        A join the declarative read cannot do: the mailbox type lives in the Mailboxes cache,
        the account state in the Users cache, and they meet on ExternalDirectoryObjectId.
        Both are cached, so this needs no live call - the classic standard read Get-Mailbox
        live because the cache did not carry recipientTypeDetails at the time.

        Only unlicensed cloud-only members qualify: a licensed account behind a room mailbox
        is somebody's real sign-in, and disabling a directory-synced one is rejected anyway.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_ })
    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Users.Count -eq 0 -or $Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Candidates = @{}
    foreach ($User in $Users) {
        if ($User.accountEnabled -ne $true) { continue }
        if ($User.onPremisesSyncEnabled -eq $true) { continue }
        if ($User.userType -ne 'Member') { continue }
        if (@($User.assignedLicenses).Count -gt 0) { continue }
        $Candidates["$($User.id)"] = $User
    }

    $Offending = @($Mailboxes | Where-Object {
            $_.recipientTypeDetails -in @('RoomMailbox', 'EquipmentMailbox') -and
            $Candidates.ContainsKey("$($_.ExternalDirectoryObjectId)")
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending | ForEach-Object { "$($_.UPN ?? $_.primarySmtpAddress)" } | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.ExternalDirectoryObjectId)" } })
        }
    }
}
