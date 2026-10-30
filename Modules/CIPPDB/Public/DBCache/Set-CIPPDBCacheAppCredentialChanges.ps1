function Set-CIPPDBCacheAppCredentialChanges {
    <#
    .SYNOPSIS
        Caches the credentials added to app registrations and service principals in the last 30 days

    .DESCRIPTION
        Reads ApplicationManagement events from the directory audit log (30 days of history needs Entra ID P1)
        and keeps one row per credential (secret or certificate) an event added or removed: the object, its key
        id, the action and who made the change, a user or an app. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache credential changes for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching app credential changes' -sev Debug

        $Start = [datetime]::UtcNow.AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=category eq 'ApplicationManagement' and activityDateTime ge $Start&`$select=activityDateTime,activityDisplayName,initiatedBy,targetResources&`$top=999"
        $Rows = @(ConvertFrom-CIPPCredentialAuditEvent -Events @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true))

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialChanges' -Data $Rows -AddCount
        } else {
            # Read successfully with no credential added: record the empty set so the report knows the log was checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialChanges' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) app credential changes" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache app credential changes: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
