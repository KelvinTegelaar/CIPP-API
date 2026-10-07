function Get-CIPPBaselineSafeSendersDisableState {
    <#
    .SYNOPSIS
        Prepare hook for SafeSendersDisable: an always-compliant state plus the mailbox list to
        sweep.
    .DESCRIPTION
        A REMEDIATE-ONLY standard. Per-mailbox junk configuration is not cached anywhere and
        reading it would cost one Get-MailboxJunkEmailConfiguration per mailbox on every
        compare, so there is no state to grade. Rather than invent a verdict, the hook reports
        the same constant on both sides: the row always reads compliant and says why.

        The work still happens - the definition sets checkBeforeRun false, so the engine writes
        on every run where remediation is enabled regardless of the compare, and the sweep
        clears TrustedSendersAndDomains for every mailbox.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Explanation = 'This is a remediate only standard. This means we cannot read the status, and always resolve it for all items'

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })

    @{
        Expected = [PSCustomObject]@{ state = $Explanation }
        Current  = [PSCustomObject]@{
            state   = $Explanation
            targets = @($Mailboxes | Where-Object { $_.UPN } | ForEach-Object { [PSCustomObject]@{ id = "$($_.UPN)" } })
        }
    }
}
