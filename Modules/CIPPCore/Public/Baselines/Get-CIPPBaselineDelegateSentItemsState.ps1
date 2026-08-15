function Get-CIPPBaselineDelegateSentItemsState {
    <#
    .SYNOPSIS
        Prepare hook for DelegateSentItems: mailboxes not copying sent-as / send-on-behalf
        mail into the shared mailbox.
    .DESCRIPTION
        Either flag being false is enough to offend - the classic standard sets both in one
        write, so a mailbox with one set and one clear is still wrong.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Types = if ("$($Item.Variables.IncludeUserMailboxes)" -in @('False', 'false', '0')) { @('SharedMailbox') } else { @('UserMailbox', 'SharedMailbox') }
    $Offending = @($Mailboxes | Where-Object {
            $_.recipientTypeDetails -in $Types -and
            ($_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false)
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.UPN)" } })
        }
    }
}
