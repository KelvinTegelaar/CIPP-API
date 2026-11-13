function Set-CIPPDBCacheServicePrincipalRoleChanges {
    <#
    .SYNOPSIS
        Caches the directory roles assigned to service principals in the last 30 days

    .DESCRIPTION
        Reads RoleManagement events and the 'Add member to group' events of role-assignable groups from the
        directory audit log (30 days of history needs Entra ID P1) and keeps one row per role or group a service
        principal was added to, and who did it, a user or an app. The report keeps only the groups that hold a
        role. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache role changes for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service principal role changes' -sev Debug

        $Start = [datetime]::UtcNow.AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $Select = '$select=id,activityDateTime,activityDisplayName,initiatedBy,targetResources&$top=999'
        $Filters = [System.Collections.Generic.List[string]]::new()
        $Filters.Add("category eq 'RoleManagement' and activityDateTime ge $Start")
        # Only role-assignable groups can hold a directory role; the group log as a whole runs to hundreds of thousands of events
        $GroupIds = @(foreach ($Group in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/groups?$filter=isAssignableToRole eq true&$select=id&$top=999' -tenantid $TenantFilter)) { [string]$Group.id })
        # 20 ids per read keeps the URL near 1 KB; the log rejects 'in', so the ids are or-ed
        for ($i = 0; $i -lt $GroupIds.Count; $i += 20) {
            $IdFilter = @(foreach ($Id in $GroupIds[$i..([Math]::Min($i + 19, $GroupIds.Count - 1))]) { "t/id eq '$Id'" }) -join ' or '
            $Filters.Add("category eq 'GroupManagement' and activityDisplayName eq 'Add member to group' and activityDateTime ge $Start and targetResources/any(t:$IdFilter)")
        }
        $Events = [System.Collections.Generic.List[object]]::new()
        foreach ($Filter in $Filters) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$Filter&$Select" -tenantid $TenantFilter -AsApp $true -Stream | ForEach-Object {
                foreach ($Target in $_.targetResources) {
                    if ($Target.type -eq 'ServicePrincipal') { $Events.Add($_); break }
                }
            }
        }
        $Rows = @(ConvertFrom-CIPPRoleAuditEvent -Events $Events.ToArray())

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalRoleChanges' -Data $Rows -AddCount
        } else {
            # Read successfully with no role assigned: record the empty set so the report knows the log was checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalRoleChanges' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) service principal role changes" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache service principal role changes: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
