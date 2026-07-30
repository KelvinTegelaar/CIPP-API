function Get-CippAccessScopeVersion {
    <#
    .SYNOPSIS
        Current version stamp for cached access scope rules.

    .DESCRIPTION
        Access scope rules are derived from CustomRoles, AccessRoleGroups and tenant group
        membership, and are cached per worker. Those inputs are shared, and one worker has no way
        to reach into another's memory, so invalidation goes through this stamp instead: every
        worker keys its cache on the current value, and Clear-CippAccessScopeCache bumps it
        whenever the underlying definitions change.

        The stamp is itself memoised for a short window so a warm request costs no storage read at
        all. That window is the upper bound on how long a role change takes to reach a worker that
        is already warm.

        A read failure returns a fresh value rather than the last known one. That forces a miss and
        a recompute from source, so a storage blip costs latency instead of serving a scope that
        may no longer be correct.

    .EXAMPLE
        Get-CippAccessScopeVersion

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    # How long a worker trusts its copy of the stamp, and therefore the worst case delay before a
    # role change reaches a worker that is already warm. The worker that made the change clears
    # its own memo, so this only applies to the others. Kept short deliberately: the cost is one
    # small table read per worker per window, which is nothing next to an operator changing a role
    # and being unable to tell whether it took effect.
    $MemoSeconds = 10
    $Now = (Get-Date).ToUniversalTime()

    if ($script:CippAccessScopeVersionMemo -and $script:CippAccessScopeVersionMemo.Expires -gt $Now) {
        return $script:CippAccessScopeVersionMemo.Version
    }

    try {
        $Table = Get-CIPPTable -tablename 'CacheVersions'
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CacheVersion' and RowKey eq 'AccessScope'"
        $Version = if ($Entity.Version) { [string]$Entity.Version } else { 'initial' }
    } catch {
        Write-Warning "Could not read the access scope cache version, forcing a recompute. $($_.Exception.Message)"
        return [string][guid]::NewGuid()
    }

    $script:CippAccessScopeVersionMemo = @{
        Version = $Version
        Expires = $Now.AddSeconds($MemoSeconds)
    }

    return $Version
}
