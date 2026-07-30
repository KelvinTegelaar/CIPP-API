function Clear-CippTokenCache {
    <#
    .SYNOPSIS
        Invalidates cached Graph tokens so the next request acquires a fresh one.

    .DESCRIPTION
        Cached access tokens carry the scopes that were consented at the time they were
        issued. After a consent change (CPV refresh/reset, permission update, SAM app
        change) a cached token still presents the OLD scopes, so calls keep failing with
        "Insufficient permission(s)" until the entry expires on its own. Call this
        immediately after any consent change.

        Safe to call when the CIPP.CIPPTokenCache type is unavailable (e.g. running
        outside the Craft host) - it becomes a no-op.

    .PARAMETER TenantFilter
        Tenant (GUID) whose cached tokens should be dropped. Omit to clear every entry.

    .EXAMPLE
        Clear-CippTokenCache -TenantFilter $TenantFilter

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $TenantFilter
    )

    if ($null -eq ('CIPP.CIPPTokenCache' -as [type])) {
        Write-Verbose 'CIPP.CIPPTokenCache is not available; skipping token cache invalidation.'
        return 0
    }

    $Target = if ($TenantFilter) { $TenantFilter } else { 'all tenants' }
    if (-not $PSCmdlet.ShouldProcess($Target, 'Invalidate cached Graph tokens')) { return 0 }

    try {
        $Removed = if ($TenantFilter) {
            [CIPP.CIPPTokenCache]::RemoveByTenant($TenantFilter)
        } else {
            [CIPP.CIPPTokenCache]::Clear()
        }
        Write-Information "Invalidated $Removed cached token(s) for $Target."
        return $Removed
    } catch {
        # Never let cache invalidation break the consent flow that called it.
        Write-Warning "Could not invalidate the token cache for $Target : $($_.Exception.Message)"
        return 0
    }
}
