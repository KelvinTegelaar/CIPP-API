function Set-CIPPDBCacheServicePrincipalSignInActivities {
    <#
    .SYNOPSIS
        Caches the last sign-in of every service principal in a tenant

    .DESCRIPTION
        Reads the Entra sign-in activity report (reports/servicePrincipalSignInActivities): one row per app
        with its last sign-in as a client or resource, delegated or app-only. Needs Entra ID P1. A failed
        read writes nothing, so an app is never reported idle because the report could not be read.

    .PARAMETER TenantFilter
        The tenant to cache service principal sign-in activity for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service principal sign-in activity' -sev Debug

        $CachedCount = 0
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities' -tenantid $TenantFilter -Stream | ForEach-Object {
                $CachedCount++
                $Writer.Process($_)
            }
            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached sign-in activity for $CachedCount service principals" -sev Debug
            } else {
                # Read successfully with no activity: record the empty set so every app reads as having no sign-in.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 service principal sign-in activities (none found)' -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache service principal sign-in activity (needs Entra ID P1): $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
