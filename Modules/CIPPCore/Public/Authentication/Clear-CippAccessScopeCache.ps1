function Clear-CippAccessScopeCache {
    <#
    .SYNOPSIS
        Invalidate cached access scope rules across every worker.

    .DESCRIPTION
        Bumps the shared version stamp the access caches key on, so every worker misses and
        recomputes from source, and drops this worker's caches immediately.

        Propagation is not instant on the other workers. They each memo the stamp for a short
        window (see Get-CippAccessScopeVersion), so a change lands there within that window.

        Call this from anything that changes what a role is allowed to do or see: custom role
        definitions, role IP ranges, access role group mappings, and tenant group membership.
        Missing a call site, a failed stamp write or a direct table edit does not cause indefinite
        staleness: every cache entry also expires after a few minutes.

        A failure is logged rather than thrown. Failing the role save the operator just made
        because a cache table hiccuped would be the worse outcome, and the expiry bounds the damage.

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

    try {
        $Table = Get-CIPPTable -tablename 'CacheVersions'
        $Entity = @{
            PartitionKey = 'CacheVersion'
            RowKey       = 'AccessScope'
            Version      = [string][guid]::NewGuid()
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    } catch {
        Write-LogMessage -API 'AccessScopeCache' -message "Failed to invalidate the access scope cache. Other workers will keep their current roles until the cache expires. $($_.Exception.Message)" -Sev 'Error'
    }
    # After the stamp is written, so this worker's next read gets the new one
    $script:CippAccessScopeRuleCache = @{}
    $script:CippRoleIPRangeCache = $null
    $script:CippRolePermissionCache = $null
    $script:CippAccessScopeVersionMemo = $null
}
