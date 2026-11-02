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
        as 'principal', the same shape the PIM schedule caches get from $expand=principal. When the
        principal is a (role-assignable) group, its service principal members are stored as
        'servicePrincipalMembers': they hold the role through the group.

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

        $AppMembers = @{}
        $GroupRequests = [System.Collections.Generic.List[object]]::new()
        foreach ($PrincipalId in $PrincipalIds) {
            if ($Principals[$PrincipalId].'@odata.type' -eq '#microsoft.graph.group') {
                $GroupRequests.Add(@{ id = $PrincipalId; method = 'GET'; url = "groups/$PrincipalId/members/microsoft.graph.servicePrincipal?`$select=id,displayName,appId&`$top=999" })
            }
        }
        if ($GroupRequests.Count -gt 0) {
            foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $GroupRequests.ToArray())) {
                if ([int]$Response.status -eq 200) { $AppMembers[[string]$Response.id] = @($Response.body.value) }
            }
        }

        $Records = foreach ($Assignment in $Assignments) {
            [PSCustomObject]@{
                id                      = $Assignment.id
                principalId             = $Assignment.principalId
                roleDefinitionId        = $Assignment.roleDefinitionId
                directoryScopeId        = $Assignment.directoryScopeId
                principal               = $Principals[$Assignment.principalId]
                servicePrincipalMembers = $AppMembers[[string]$Assignment.principalId]
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
