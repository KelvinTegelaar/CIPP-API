function Set-CIPPDBCacheAppCredentialSignInActivities {
    <#
    .SYNOPSIS
        Caches when each app credential last signed in

    .DESCRIPTION
        Reads the Entra credential sign-in activity report (reports/appCredentialSignInActivities): one row per
        secret or certificate that signed in, with its key id, the app, whether it sits on the app registration
        or the service principal, and its last sign-in. Needs Entra ID P1. A credential without a row has no
        sign-in recorded. A failed read writes nothing, so no credential is reported unused because the report
        could not be read.

    .PARAMETER TenantFilter
        The tenant to cache credential sign-in activity for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching app credential sign-in activity' -sev Debug

        $CachedCount = 0
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialSignInActivities' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/appCredentialSignInActivities' -tenantid $TenantFilter -Stream | ForEach-Object {
                $CachedCount++
                $Writer.Process($_)
            }
            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached sign-in activity for $CachedCount app credentials" -sev Debug
            } else {
                # Read successfully with no activity: record the empty set so every credential reads as unused.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialSignInActivities' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached 0 app credential sign-in activities (none found)' -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app credential sign-in activity (needs Entra ID P1): $($_.Exception.Message)" -sev Error
        # Rethrow so the cache run counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
