function Get-CIPPBaselineMailboxDefaultAuditSetState {
    <#
    .SYNOPSIS
        Prepare hook for MailboxDefaultAuditSet: mailboxes whose audit actions were customised
        away from the Microsoft-managed defaults.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Types = @('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox')
    $Offending = @($Mailboxes.Where({
                $Set = @($_.DefaultAuditSet)
                $_.recipientTypeDetails -in $Types -and ('Admin' -notin $Set -or 'Delegate' -notin $Set -or 'Owner' -notin $Set)
            }))

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.UPN)" } })
        }
    }
}
