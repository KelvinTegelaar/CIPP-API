function Get-CIPPBaselineDisableSharedMailboxState {
    <#
    .SYNOPSIS
        Prepare hook for DisableSharedMailbox: shared and scheduling mailboxes whose Entra
        account is still enabled.
    .DESCRIPTION
        Same join as DisableResourceMailbox, on the Mailboxes and Users caches. The classic
        standard read the adminapi Mailbox endpoint live; the cache carries
        recipientTypeDetails and ExternalDirectoryObjectId, so no live call is needed.

        NOTE - the classic filter read
            RecipientTypeDetails -eq 'SharedMailbox' -or RecipientTypeDetails -eq 'SchedulingMailbox' -and UserPrincipalName -in $UserList
        which looks like it only joins SchedulingMailbox against the user list, but does not:
        PowerShell gives -and and -or the same precedence and associates them left to right, so
        it means '(shared or scheduling) and still enabled'. Same set as the join here; the only
        real difference is that this one keys on ExternalDirectoryObjectId instead of the UPN.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    # Users is the SECOND cache: the definition declares Mailboxes, so the engine only
    # collect-on-misses that one. Reading Users directly meant a tenant that had never
    # collected it returned No Data on every run, permanently, blaming Mailboxes.
    $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users')
    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Users.Count -eq 0 -or $Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Candidates = @{}
    foreach ($User in $Users) {
        if ($User.accountEnabled -ne $true) { continue }
        if ($User.onPremisesSyncEnabled -eq $true) { continue }
        $Candidates["$($User.id)"] = $User
    }

    $Offending = @($Mailboxes | Where-Object {
            $_.recipientTypeDetails -in @('SharedMailbox', 'SchedulingMailbox') -and
            $Candidates.ContainsKey("$($_.ExternalDirectoryObjectId)")
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending | ForEach-Object { "$($_.UPN ?? $_.primarySmtpAddress)" } | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.ExternalDirectoryObjectId)" } })
        }
    }
}
