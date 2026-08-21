function Get-CIPPBaselinecalDefaultState {
    <#
    .SYNOPSIS
        Prepare hook for calDefault: calendars whose Default permission is not the configured
        level.
    .DESCRIPTION
        CalendarPermissions has no collector named after it - Set-CIPPDBCacheMailboxes writes
        it under -Types CalendarPermissions - so the read goes through Get-CIPPBaselineCacheRows
        with an explicit CollectorType. Without that the type would never be collected on a
        tenant that has not run a full mailbox collection, and the standard would sit at No
        Data forever.

        Only the 'Default' principal is graded; named delegates are somebody's deliberate
        grant and are none of this standard's business. AccessRights arrives as an array on
        some rows and a string on others, so it is joined before comparing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Permissions = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'CalendarPermissions' -CollectorType 'Mailboxes' -CollectorArgs @{ Types = 'CalendarPermissions' })
    if ($Permissions.Count -eq 0) { return @{ Current = $null } }

    $Level = "$($Item.Variables.permissionLevel)"
    $Offending = @($Permissions | Where-Object {
            $_.User -eq 'Default' -and
            (($(if ($_.AccessRights -is [array]) { $_.AccessRights -join ',' } else { "$($_.AccessRights)" })) -ne $Level)
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.Identity | Sort-Object)
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.Identity)" } })
        }
    }
}
