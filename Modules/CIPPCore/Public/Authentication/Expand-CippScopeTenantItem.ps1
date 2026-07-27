function Expand-CippScopeTenantItem {
    <#
    .SYNOPSIS
        Expand a role's tenant entries, resolving tenant groups to their member tenant ids.

    .DESCRIPTION
        Entries stored against a role are either literal tenant ids, the 'AllTenants' sentinel, or
        a tenant group reference that has to be resolved to the ids currently in that group.

        A group that cannot be expanded warns and contributes nothing, which is deliberate: the
        alternative - treating an unresolvable group as 'everything' - would widen access on the
        back of a lookup failure.

        Used by Get-CippAccessScopeRule for both the allowed and blocked lists.

    .PARAMETER Items
        The stored AllowedTenants or BlockedTenants entries.

    .PARAMETER Kind
        'allowed' or 'blocked', used only to make the warning readable.

    .EXAMPLE
        Expand-CippScopeTenantItem -Items $Permission.BlockedTenants -Kind 'blocked'

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Items,
        [string]$Kind
    )

    foreach ($Item in $Items) {
        if ($Item -is [PSCustomObject] -and $Item.type -eq 'Group') {
            try {
                $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($Item)
                $GroupMembers | ForEach-Object { $_.addedFields.customerId }
            } catch {
                Write-Warning "Failed to expand $Kind tenant group '$($Item.label)': $($_.Exception.Message)"
            }
        } else {
            $Item
        }
    }
}
