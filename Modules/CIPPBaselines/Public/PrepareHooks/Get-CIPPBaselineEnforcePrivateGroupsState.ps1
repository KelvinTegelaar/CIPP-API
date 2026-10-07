function Get-CIPPBaselineEnforcePrivateGroupsState {
    <#
    .SYNOPSIS
        Prepare hook for EnforcePrivateGroups: public Microsoft 365 groups that are not excluded.
    .DESCRIPTION
        Exclusions are keyword CONTAINS matches on the display name, not exact names - the
        classic standard used -match on an escaped keyword so an operator can exclude a whole
        naming convention with one entry.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Groups = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_ })
    if ($Groups.Count -eq 0) { return @{ Current = $null } }

    $Keywords = @(@($Item.Variables.ExcludedGroupNames) | ForEach-Object {
            if ($_ -is [string]) { $_ } else { "$($_.value ?? $_.label)" }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $Public = @($Groups | Where-Object {
            $_.groupTypes -contains 'Unified' -and $_.visibility -eq 'Public'
        } | Where-Object {
            $DisplayName = "$($_.displayName)"
            -not @($Keywords | Where-Object { $DisplayName -match [regex]::Escape($_) })
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Public.displayName | Sort-Object)
            targets   = @($Public | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
