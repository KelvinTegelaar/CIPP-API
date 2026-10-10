function Set-CIPPDBCacheOAuth2PermissionGrants {
    <#
    .SYNOPSIS
        Caches OAuth2 permission grants (delegated permissions) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache OAuth2 permission grants for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OAuth2 permission grants' -sev Debug

        $CachedCount = 0
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/oauth2PermissionGrants?$top=999' -tenantid $TenantFilter -Stream | ForEach-Object {
                $CachedCount++
                $Writer.Process($_)
            }
            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount OAuth2 permission grants" -sev Debug
            } else {
                # The request succeeded with nothing returned: write the authoritative empty set so the
                # Count marker records a completed collection and stale rows are cleared.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 OAuth2 permission grants (none found)' -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OAuth2 permission grants: $($_.Exception.Message)" -sev Error
    }
}
