function Set-CIPPDBCacheDelegatedGrantChanges {
    <#
    .SYNOPSIS
        Caches the delegated permission grants added in the last 30 days

    .DESCRIPTION
        Reads 'Add delegated permission grant' events from the directory audit log (30 days of history needs
        Entra ID P1) and keeps one row per grant: the client app, the resource API, the consent type and scopes,
        and who added it, a user or an app. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache delegated grant changes for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching delegated grant changes' -sev Debug

        $Start = [datetime]::UtcNow.AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Add delegated permission grant' and activityDateTime ge $Start&`$select=id,activityDateTime,activityDisplayName,initiatedBy,targetResources&`$top=999"
        $Rows = @(ConvertFrom-CIPPGrantAuditEvent -Events @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true))

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DelegatedGrantChanges' -Data $Rows -AddCount
        } else {
            # Read successfully with no grant added: record the empty set so the report knows the log was checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DelegatedGrantChanges' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) delegated grant changes" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache delegated grant changes: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
