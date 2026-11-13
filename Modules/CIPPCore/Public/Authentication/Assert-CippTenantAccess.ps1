function Assert-CippTenantAccess {
    <#
    .SYNOPSIS
        Refuses the request unless the caller's roles cover every tenant or tenant group it will act on.
    .DESCRIPTION
        For AnyTenant endpoints whose targets come from somewhere the dispatcher does not check, such as a
        tenant selector list. Runs the dispatcher's per-role decision on those targets against the full
        tenant and group lists, and throws an UnauthorizedAccessException carrying the standard message,
        which Get-CippErrorStatusCode turns into a 403.
    .PARAMETER TenantFilter
        Tenant domains, customerIds, 'AllTenants', or tenant selector objects ({ value; label; type }).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [AllowNull()][AllowEmptyCollection()]$TenantFilter
    )
    # The request scope hides tenants and groups outside the caller's access; the decision needs them to see blocks.
    $SavedTenants = if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value }
    $SavedGroups = if ($script:CippAllowedGroupsStorage) { $script:CippAllowedGroupsStorage.Value }
    try {
        if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value = $null }
        if ($script:CippAllowedGroupsStorage) { $script:CippAllowedGroupsStorage.Value = $null }
        $null = Test-CIPPAccess -Request $Request -TenantFilter $TenantFilter
    } catch {
        throw [System.UnauthorizedAccessException]::new($_.Exception.Message)
    } finally {
        if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value = $SavedTenants }
        if ($script:CippAllowedGroupsStorage) { $script:CippAllowedGroupsStorage.Value = $SavedGroups }
    }
}
