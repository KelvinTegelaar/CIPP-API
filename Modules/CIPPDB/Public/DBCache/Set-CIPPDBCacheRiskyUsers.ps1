function Set-CIPPDBCacheRiskyUsers {
    <#
    .SYNOPSIS
        Caches risky users from Identity Protection for a tenant

    .PARAMETER TenantFilter
        The tenant to cache risky users for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching risky users from Identity Protection' -sev Debug

        # Requires P2 or Governance licensing
        $CachedCount = 0
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyUsers' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyUsers' -tenantid $TenantFilter -Stream | ForEach-Object {
                $CachedCount++
                $Writer.Process($_)
            }
            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount risky users successfully" -sev Debug
            } else {
                # The request succeeded with nothing returned: write the authoritative empty set so the
                # Count marker records a completed collection and stale rows are cleared.
                Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyUsers' -Data @() -AddCount -ClearOnEmpty
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No risky users found or Identity Protection not available' -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache risky users: $($_.Exception.Message)" `
            -sev Warning `
            -LogData (Get-CippException -Exception $_)
    }
}
