function Initialize-CippRequestContext {
    <#
    .SYNOPSIS
        Reset the per-invocation context slots at the start of a request.

    .DESCRIPTION
        The tenant scope, group scope, invocation id and user role cache live in module scoped
        AsyncLocal slots so deep helpers (Get-Tenants, Get-TenantGroups) can read the current
        request's access scope without every call site threading it through as a parameter.

        AsyncLocal does not give per-request isolation in this host. Both Craft and the Azure
        Functions PowerShell worker reuse runspaces and execution contexts between invocations,
        so a value written by one request is still visible to the next request that lands on the
        same worker. Whatever is left behind is inherited, and a request whose access is
        unrestricted has no reason to overwrite it - which is how a restricted user's tenant
        scope ends up silently filtering an unrestricted user's results.

        Every slot is therefore reset here, unconditionally, before any of them is read.

    .EXAMPLE
        Initialize-CippRequestContext

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CippInvocationIdStorage) {
        $script:CippInvocationIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    if (-not $script:CippAllowedTenantsStorage) {
        $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    if (-not $script:CippAllowedGroupsStorage) {
        $script:CippAllowedGroupsStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    if (-not $script:CippUserRolesStorage) {
        $script:CippUserRolesStorage = [System.Threading.AsyncLocal[hashtable]]::new()
    }

    # Clear anything inherited from an earlier invocation on this worker. Consumers treat a null
    # scope as 'unrestricted', so a stale value can only ever hide data that the caller is
    # entitled to see - it never grants access. That makes the symptom silent rather than loud,
    # which is exactly why it has to be cleared here rather than relied on to be overwritten.
    $script:CippInvocationIdStorage.Value = $null
    $script:CippAllowedTenantsStorage.Value = $null
    $script:CippAllowedGroupsStorage.Value = $null
    $script:CippUserRolesStorage.Value = @{}
}
