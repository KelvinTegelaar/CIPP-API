function Set-CIPPDBCacheExoAppRoleAssignments {
    <#
    .SYNOPSIS
        Caches the Exchange RBAC for Applications role assignments

    .DESCRIPTION
        Exchange can give an app mailbox access through its own role assignments, which Entra does not show. Keeps
        one row per assignment of an 'Application *' role: the app's appId and service principal id, the scope and
        when it was created. A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache Exchange application role assignments for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange application role assignments' -sev Debug

        $Rows = @(Get-CIPPExoAppRoleAssignment -TenantFilter $TenantFilter)

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAppRoleAssignments' -Data $Rows -AddCount
        } else {
            # Read successfully with no assignment: record the empty set so the report knows Exchange was checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAppRoleAssignments' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) Exchange application role assignments" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Exchange application role assignments: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
