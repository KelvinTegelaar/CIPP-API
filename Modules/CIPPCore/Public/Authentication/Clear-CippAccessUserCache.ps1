function Clear-CippAccessUserCache {
    <#
    .SYNOPSIS
        Clear the cached per-user role resolutions.

    .DESCRIPTION
        Deletes every cached user-to-role resolution (the AccessUser partition of
        cacheAccessUserRoles) so the next request re-resolves Entra group membership instead of
        reusing roles derived from the old group mappings. The cache repopulates on demand.

        Call this from anything that changes which Entra group maps to a CIPP role. The
        companion Clear-CippAccessScopeCache covers what a role is allowed to see; this covers
        which roles a user resolves to. Callers that also maintain the allowedUsers projection
        should fire Start-UserSyncTimer and invalidate CRAFT's user cache alongside this.

        A failure is logged rather than thrown - the mapping change the operator just saved is
        already durable, and the cache TTL bounds how long a missed clear can linger.

    .EXAMPLE
        Clear-CippAccessUserCache

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('cacheAccessUserRoles', 'Clear cached user role resolutions')) {
        return
    }

    try {
        $Table = Get-CippTable -TableName 'cacheAccessUserRoles'
        $CachedUsers = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AccessUser'"
        foreach ($CachedUser in @($CachedUsers)) {
            if ($CachedUser) {
                Remove-CIPPAzDataTableEntity -Force @Table -Entity $CachedUser
            }
        }
    } catch {
        Write-LogMessage -API 'AccessUserCache' -message "Failed to clear cached user roles. Users keep their previously resolved roles until the cache expires. $($_.Exception.Message)" -Sev 'Error'
    }
}
