function Get-CIPPBaselineEnableOnlineArchivingState {
    <#
    .SYNOPSIS
        Prepare hook for EnableOnlineArchiving: licensed user mailboxes with no archive.
    .DESCRIPTION
        Scoped to the two mailbox plans that carry an archive entitlement, exactly as the
        classic standard queried Get-Mailbox once per plan. A mailbox on any other plan cannot
        have an archive enabled, so grading it would report drift no remediation can clear.

        The cached MailboxPlan name carries a tenant-specific suffix
        (ExchangeOnlineEnterprise-a1b2c3...), so it is matched by prefix. The mailbox is
        captured into a named variable first because $_ is rebound inside the inner
        Where-Object.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $ArchivePlans = @('ExchangeOnline', 'ExchangeOnlineEnterprise')
    $Offending = @($Mailboxes | Where-Object {
            $Mailbox = $_
            $Mailbox.recipientTypeDetails -eq 'UserMailbox' -and
            $Mailbox.ArchiveEnabled -ne $true -and
            @($ArchivePlans | Where-Object { "$($Mailbox.MailboxPlan)".StartsWith($_) }).Count -gt 0
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.UPN)" } })
        }
    }
}
