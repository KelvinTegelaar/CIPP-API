function Set-CIPPDBCacheRoleDefinitions {
    <#
    .SYNOPSIS
        Caches every Entra directory role definition for a tenant

    .DESCRIPTION
        Built-in and custom role definitions, whether or not anyone holds them. The Roles cache only
        has directoryRoles (roles that have been activated), so this is what lets the cached Roles &
        Assignments view list roles nobody holds, tell built-in from custom roles and flag custom
        roles Microsoft marks as privileged.

    .PARAMETER TenantFilter
        The tenant to cache role definitions for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role definitions' -sev Debug
        # beta: isPrivileged is not on the v1.0 unifiedRoleDefinition and a $select of it fails the request.
        $Definitions = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions?$select=id,templateId,displayName,description,isBuiltIn,isEnabled,isPrivileged' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleDefinitions' -Data @($Definitions) -AddCount -ClearOnEmpty
        $Definitions = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role definitions successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role definitions: $($_.Exception.Message)" -sev Error
    }
}
