function Get-CippRequestContext {
    <#
    .SYNOPSIS
        Return the per-invocation access context for the current request.

    .DESCRIPTION
        Accessor for the context slots managed by Initialize-CippRequestContext.

        These slots are held in CIPPCore module scope. `$script:` is per-module, so a function in
        another module - CIPPHTTP, for example - that reads $script:CippAllowedTenantsStorage
        directly gets that module's own, permanently empty, variable rather than this one.
        Diagnostics outside CIPPCore must go through this function or they will report that no
        scoping is applied no matter what is actually in force.

    .EXAMPLE
        $Context = Get-CippRequestContext
        $Context.AllowedTenants

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $InvocationId = if ($script:CippInvocationIdStorage) { $script:CippInvocationIdStorage.Value } else { $null }
    $AllowedTenants = if ($script:CippAllowedTenantsStorage) { $script:CippAllowedTenantsStorage.Value } else { $null }
    $AllowedGroups = if ($script:CippAllowedGroupsStorage) { $script:CippAllowedGroupsStorage.Value } else { $null }

    # Count only. The keys are user principal names and the diagnostic endpoint that surfaces
    # this is gated on CIPP.Core.Read, which is not a high enough bar to hand out a list of who
    # else has been using this worker.
    $CachedUserRoleCount = if ($script:CippUserRolesStorage -and $script:CippUserRolesStorage.Value) {
        $script:CippUserRolesStorage.Value.Count
    } else {
        0
    }

    return [PSCustomObject]@{
        InvocationId        = $InvocationId
        AllowedTenants      = $AllowedTenants
        AllowedGroups       = $AllowedGroups
        CachedUserRoleCount = $CachedUserRoleCount
    }
}
