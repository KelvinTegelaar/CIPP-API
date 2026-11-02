function Clear-CippAccessScopeCache {
    <#
    .SYNOPSIS
        Invalidate cached access scope rules across every worker.

    .DESCRIPTION
        Bumps the shared version stamp that Get-CippAccessScopeRule keys on, so every worker misses
        and recomputes from source, and drops this worker's caches immediately.

        Propagation is not instant on the other workers. They each memo the stamp for a short
        window (see Get-CippAccessScopeVersion), so a change lands there within that window rather
        than on the very next request. Verified behaviour, not an assumption.

        Call this from anything that changes what a role is allowed to see: custom role
        definitions, access role group mappings, and tenant group membership. Missing a call site
        does not cause indefinite staleness - the rule cache TTL still expires entries - but it
        does mean an operator can save a role change and not see it take effect straight away.

        A failure is logged rather than thrown. Failing the role save the operator just made
        because a cache table hiccuped would be the worse outcome, and the TTL bounds the damage.

    .EXAMPLE
        Clear-CippAccessScopeCache

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('access scope cache', 'Invalidate')) {
        return
    }

    $script:CippAccessScopeRuleCache = @{}
    $script:CippAccessScopeVersionMemo = $null

    try {
        $Table = Get-CIPPTable -tablename 'CacheVersions'
        $Entity = @{
            PartitionKey = 'CacheVersion'
            RowKey       = 'AccessScope'
            Version      = [string][guid]::NewGuid()
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    } catch {
        Write-LogMessage -API 'AccessScopeCache' -message "Failed to invalidate the access scope cache. Other workers will keep their current rules until the cache expires. $($_.Exception.Message)" -Sev 'Error'
    }
}
