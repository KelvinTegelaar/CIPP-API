function Resolve-CippRoleTenantEntry {
    <#
    .SYNOPSIS
        Render one stored tenant entry from a role definition for display.

    .DESCRIPTION
        A stored entry is either a tenant group object, the literal 'AllTenants' sentinel, or a
        customer id.

        An id that no longer resolves against the current tenant list used to be dropped silently,
        and a list that dropped to empty was then reported as unrestricted. The effect was that a
        role blocking a tenant CIPP could not currently see rendered as blocking nothing at all -
        a real restriction shown as absent, which is the worst direction for this to fail in.

        Unresolvable ids are now returned with the id as their value and marked Unresolved, so the
        entry stays visible and still carries its customerId.

        Used by Invoke-ListCustomRole for both AllowedTenants and BlockedTenants so the two lists
        cannot drift apart.

    .PARAMETER Entry
        A single deserialised entry from AllowedTenants or BlockedTenants.

    .PARAMETER TenantList
        Tenants to resolve customer ids against.

    .EXAMPLE
        Resolve-CippRoleTenantEntry -Entry $StoredEntry -TenantList (Get-Tenants -IncludeErrors)

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Entry,
        $TenantList
    )

    if ($Entry -is [PSCustomObject] -and $Entry.type -eq 'Group') {
        return [PSCustomObject]@{
            type  = 'Group'
            value = $Entry.value
            label = $Entry.label
        }
    }

    # Not a tenant id, and it must survive the lookup below rather than be resolved away
    if ($Entry -is [string] -and $Entry -eq 'AllTenants') {
        return 'AllTenants'
    }

    $TenantId = $Entry
    $TenantInfo = $TenantList | Where-Object { $_.customerId -eq $TenantId } | Select-Object -First 1

    if ($TenantInfo) {
        return [PSCustomObject]@{
            type        = 'Tenant'
            value       = $TenantInfo.defaultDomainName
            label       = "$($TenantInfo.displayName) ($($TenantInfo.defaultDomainName))"
            addedFields = @{
                defaultDomainName = $TenantInfo.defaultDomainName
                displayName       = $TenantInfo.displayName
                customerId        = $TenantInfo.customerId
            }
        }
    }

    return [PSCustomObject]@{
        type        = 'Tenant'
        value       = $TenantId
        label       = "$TenantId (tenant not found)"
        Unresolved  = $true
        addedFields = @{
            customerId = $TenantId
        }
    }
}
