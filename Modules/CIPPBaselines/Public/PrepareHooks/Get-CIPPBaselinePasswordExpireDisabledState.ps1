function Get-CIPPBaselinePasswordExpireDisabledState {
    <#
    .SYNOPSIS
        Prepare hook for PasswordExpireDisabled: verified domains whose passwords still expire.
    .DESCRIPTION
        Subdomains are excluded because they inherit the parent's password policy - writing to
        them is rejected, and grading them would report drift no remediation can clear.

        Each target carries the notification window it should end up with: Graph refuses a
        never-expires validity period while the window is unset, so a domain that has none
        gets the classic standard's 14 days and one that already has a window keeps it.
        Sending it unconditionally is equivalent to the old conditional body and keeps the
        write spec uniform.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Domains = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Domains' | Where-Object { $_ })
    if ($Domains.Count -eq 0) { return @{ Current = $null } }

    $Ids = @($Domains.id)
    $SubDomains = @(foreach ($Id in $Ids) {
            foreach ($Parent in $Ids) {
                if ($Id -ne $Parent -and "$Id".EndsWith(".$Parent")) { $Id; break }
            }
        })

    $Offending = @($Domains | Where-Object {
            $_.isVerified -eq $true -and
            $_.passwordValidityPeriodInDays -ne 2147483647 -and
            $_.id -notin $SubDomains
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.id | Sort-Object)
            targets   = @($Offending | ForEach-Object {
                    [PSCustomObject]@{
                        id                                = "$($_.id)"
                        passwordNotificationWindowInDays  = $(if ($null -eq $_.passwordNotificationWindowInDays) { 14 } else { [int]$_.passwordNotificationWindowInDays })
                    }
                })
        }
    }
}
