function Get-CIPPAlertRoleEscalableGroups {
    <#
    .SYNOPSIS
        Flags non-role-assignable groups in Entra directory role paths.

    .DESCRIPTION
        Scans Entra directory role assignments where the role principal is a group. Flags:
        1) direct role-assigned groups that are not marked isAssignableToRole, and
        2) non-role-assignable nested groups found via transitive group membership under a role-assigned group.
        Findings include path type, role-assigned group details, impacted group details, and human-readable role name.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $groups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName,isAssignableToRole&`$top=999" -tenantid $TenantFilter)
        if (-not $groups -or $groups.Count -eq 0) {
            Write-Information "Get-CIPPAlertRoleEscalableGroups: no groups returned for $TenantFilter"
            return
        }
        $groupById = @{}
        foreach ($g in $groups) {
            if (-not $g.id) { continue }
            $groupById["$($g.id)"] = $g
        }

        $roleDefinitions = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions?`$select=id,displayName&`$top=999" -tenantid $TenantFilter)
        $roleDefById = @{}
        foreach ($rd in $roleDefinitions) {
            if (-not $rd.id) { continue }
            $roleDefById["$($rd.id)"] = $rd
        }

        $roleAssignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$select=id,principalId,roleDefinitionId,directoryScopeId,appScopeId&`$top=999" -tenantid $TenantFilter)
        if (-not $roleAssignments -or $roleAssignments.Count -eq 0) {
            Write-Information "Get-CIPPAlertRoleEscalableGroups: no role assignments returned for $TenantFilter"
            return
        }

        $findings = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $transitiveNestedGroupIdsByRoot = @{}

        foreach ($assignment in $roleAssignments) {
            $principalId = "$($assignment.principalId)"
            if (-not $principalId) { continue }

            if (-not $groupById.ContainsKey($principalId)) { continue }
            $rootGroup = $groupById[$principalId]
            if (-not $rootGroup) { continue }

            $roleDefId = "$($assignment.roleDefinitionId)"
            $roleDef = if ($roleDefId) { $roleDefById[$roleDefId] } else { $null }
            $roleName = if ($roleDef -and $roleDef.displayName) { $roleDef.displayName } else { 'Unknown role' }
            $scope = if ($assignment.directoryScopeId) { "$($assignment.directoryScopeId)" } elseif ($assignment.appScopeId) { "$($assignment.appScopeId)" } else { '/' }

            if ($rootGroup.isAssignableToRole -ne $true) {
                $dedupeKey = "D|$principalId|$roleDefId|$scope"
                if (-not $seen.Add($dedupeKey)) { continue }

                $findings.Add([PSCustomObject]@{
                        PathType                      = 'Direct'
                        RoleAssignedGroupId           = $rootGroup.id
                        RoleAssignedGroupDisplayName  = $rootGroup.displayName
                        GroupDisplayName              = $rootGroup.displayName
                        GroupId                       = $rootGroup.id
                        IsAssignableToRole            = $rootGroup.isAssignableToRole
                        RoleName                      = $roleName
                        Risk                          = 'High'
                        Reason                        = 'Group has directory role assignment while not marked role-assignable; group owners/admins have an indirect role-escalation path.'
                    })
            }

            if (-not $transitiveNestedGroupIdsByRoot.ContainsKey($principalId)) {
                $nestedIds = [System.Collections.Generic.List[string]]::new()
                try {
                    $transitive = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$principalId/transitiveMembers/microsoft.graph.group?`$select=id" -tenantid $TenantFilter)
                    foreach ($m in $transitive) {
                        $mid = "$($m.id)"
                        if (-not $mid -or $mid -eq $principalId) { continue }
                        $nestedIds.Add($mid)
                    }
                } catch {
                    Write-Information "Get-CIPPAlertRoleEscalableGroups: transitiveMembers failed for group $principalId — $($_.Exception.Message)"
                }
                $transitiveNestedGroupIdsByRoot[$principalId] = $nestedIds
            }

            foreach ($nestedId in @($transitiveNestedGroupIdsByRoot[$principalId])) {
                if (-not $groupById.ContainsKey($nestedId)) { continue }
                $nestedGroup = $groupById[$nestedId]
                if (-not $nestedGroup) { continue }
                if ($nestedGroup.isAssignableToRole -eq $true) { continue }

                $dedupeKey = "N|$nestedId|$roleDefId|$scope|$principalId"
                if (-not $seen.Add($dedupeKey)) { continue }

                $findings.Add([PSCustomObject]@{
                        PathType                      = 'Nested'
                        RoleAssignedGroupId           = $rootGroup.id
                        RoleAssignedGroupDisplayName  = $rootGroup.displayName
                        GroupDisplayName              = $nestedGroup.displayName
                        GroupId                       = $nestedGroup.id
                        IsAssignableToRole            = $nestedGroup.isAssignableToRole
                        RoleName                      = $roleName
                        Risk                          = 'High'
                        Reason                        = 'Non-role-assignable group is nested (transitive member) under a group that has a directory role; group owners/admins can add members who inherit high privileged membership.'
                    })
            }
        }

        if ($findings.Count -gt 0) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data @($findings)
        } else {
            Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Role-escalable groups alert: no role-escalation group paths found" -sev 'Information'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Role-escalable groups alert failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
    }
}
