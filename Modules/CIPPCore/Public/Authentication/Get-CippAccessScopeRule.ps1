function Get-CippAccessScopeRule {
    <#
    .SYNOPSIS
        The tenant and group scope rule a custom role expresses.

    .DESCRIPTION
        Returns the rule itself - allow everything, or an explicit allow list minus a block list -
        rather than the set of tenant ids it currently resolves to.

        That distinction is the whole point of the cache. Caching the resolved id list would bake
        in a snapshot of the tenant table, so a tenant onboarded afterwards would silently stay
        invisible to the role until the entry expired: the same silent-omission failure that made
        the request scope leak so hard to spot. A rule depends only on the role definition and
        tenant group membership, both covered by the version stamp, so it stays correct however
        many tenants come and go. Callers expand it against the live tenant list at the point of
        use, which is an in-memory set operation over data they already hold.

        Cached per worker, keyed by the shared version stamp so a role change invalidates every
        worker at once, with a TTL as a backstop in case an invalidation call site is missed.

    .PARAMETER Role
        Name of the custom role.

    .EXAMPLE
        $Rule = Get-CippAccessScopeRule -Role 'helpdesk'
        if (-not $Rule.Unrestricted) { $Rule.BlockedTenants }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    $TtlMinutes = 5
    $Now = (Get-Date).ToUniversalTime()
    $Version = Get-CippAccessScopeVersion
    $CacheKey = '{0}|{1}' -f $Version, $Role

    if (-not $script:CippAccessScopeRuleCache) {
        $script:CippAccessScopeRuleCache = @{}
    }

    $Cached = $script:CippAccessScopeRuleCache[$CacheKey]
    if ($Cached -and $Cached.Expires -gt $Now) {
        return $Cached.Rule
    }

    # Throws when the role no longer exists, which callers already handle as 'this role
    # contributes no scope'
    $Permission = Get-CIPPRolePermissions -Role $Role

    $Unrestricted = ((($Permission.AllowedTenants | Measure-Object).Count -eq 0 -or
            $Permission.AllowedTenants -contains 'AllTenants') -and
        ($Permission.BlockedTenants | Measure-Object).Count -eq 0)

    $AllowAllTenants = $false
    $AllowedTenants = @()
    $BlockedTenants = @()
    $AllowedGroups = @()

    if (-not $Unrestricted) {
        $Expanded = @(Expand-CippScopeTenantItem -Items $Permission.AllowedTenants -Kind 'allowed')

        # 'AllTenants' alongside a block list means 'everything except', and the caller substitutes
        # the live tenant list. Held as a flag rather than a resolved list precisely so that
        # substitution happens at read time.
        $AllowAllTenants = $Expanded -contains 'AllTenants'
        $AllowedTenants = @($Expanded | Where-Object { $_ -ne 'AllTenants' })
        $BlockedTenants = @(Expand-CippScopeTenantItem -Items $Permission.BlockedTenants -Kind 'blocked')
        $AllowedGroups = @(
            foreach ($Item in $Permission.AllowedTenants) {
                if ($Item -is [PSCustomObject] -and $Item.type -eq 'Group') { $Item.value }
            }
        )
    }

    $Rule = [PSCustomObject]@{
        Role            = $Role
        Unrestricted    = $Unrestricted
        AllowAllTenants = $AllowAllTenants
        AllowedTenants  = $AllowedTenants
        BlockedTenants  = $BlockedTenants
        AllowedGroups   = $AllowedGroups
    }

    # Entries keyed on a superseded version are dead weight; drop the lot rather than track ages
    if ($script:CippAccessScopeRuleCache.Count -gt 200) {
        $script:CippAccessScopeRuleCache = @{}
    }
    $script:CippAccessScopeRuleCache[$CacheKey] = @{
        Rule    = $Rule
        Expires = $Now.AddMinutes($TtlMinutes)
    }

    return $Rule
}
