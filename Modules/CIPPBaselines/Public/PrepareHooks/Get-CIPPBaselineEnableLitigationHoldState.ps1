function Get-CIPPBaselineEnableLitigationHoldState {
    <#
    .SYNOPSIS
        Prepare hook for EnableLitigationHold: licensed mailboxes without litigation hold.
    .DESCRIPTION
        Licensing is the whole difficulty here - litigation hold needs an archiving or
        enterprise plan, and enabling it without one fails per mailbox. Set-CIPPDBCacheMailboxes
        precomputes LicensedForLitigationHold from the same PersistedCapabilities the classic
        standard tested by hand, so the predicate is a single flag rather than five -contains.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    $Offending = @($Mailboxes | Where-Object {
            $_.LicensedForLitigationHold -eq $true -and $_.LitigationHoldEnabled -ne $true
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.UPN)" } })
        }
    }
}
