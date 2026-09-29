function Set-CIPPDBCacheRoleAssignments {
    <#
    .SYNOPSIS
        Caches every directory role assignment for a tenant, with its principal

    .DESCRIPTION
        The unified roleManagement/directory/roleAssignments list: every active assignment including
        custom roles and administrative-unit scopes. Tenants without Entra ID P2 have no PIM API, so
        this is what the cached Roles & Assignments view reads for them (the directoryRoles members
        in the Roles cache only cover built-in roles at directory scope).

        Principals are resolved in bulk through directoryObjects/getByIds and stored on each record
        as 'principal', the same shape the PIM schedule caches get from $expand=principal.

    .PARAMETER TenantFilter
        The tenant to cache role assignments for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching role assignments' -sev Debug
        $Assignments = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId&$top=999' -tenantid $TenantFilter)

        # getByIds returns in milliseconds where $expand=principal costs seconds.
        $Principals = @{}
        $PrincipalIds = @($Assignments.principalId | Where-Object { $_ } | Sort-Object -Unique)
        for ($i = 0; $i -lt $PrincipalIds.Count; $i += 1000) {
            $Body = ConvertTo-Json -InputObject @{ ids = @($PrincipalIds[$i..([Math]::Min($i + 999, $PrincipalIds.Count - 1))]) } -Compress
            $Resolved = New-GraphPOSTRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName,appId' -body $Body
            foreach ($Principal in @($Resolved.value)) { $Principals[$Principal.id] = $Principal }
        }

        $Records = foreach ($Assignment in $Assignments) {
            [PSCustomObject]@{
                id               = $Assignment.id
                principalId      = $Assignment.principalId
                roleDefinitionId = $Assignment.roleDefinitionId
                directoryScopeId = $Assignment.directoryScopeId
                principal        = $Principals[$Assignment.principalId]
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'RoleAssignments' -Data @($Records) -AddCount -ClearOnEmpty
        $Assignments = $null
        $Records = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached role assignments successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache role assignments: $($_.Exception.Message)" -sev Error
    }
}
