function Invoke-ListPIMRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .SYNOPSIS
        List Entra directory roles grouped with their PIM assignment breakdown.
    .DESCRIPTION
        Returns one row per role (per tenant when AllTenants is selected) with the role's definition details, how many principals hold it permanently, eligibly or with a time-bound active assignment, the role's PIM policy summary, a slim Members list and the full assignment rows for drill-in. Roles nobody holds are included for a single tenant so the result is also the role catalogue. Powers the Roles & PIM page; ListRoles keeps its original per-definition shape and ListRoleAssignments stays one flat row per assignment.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    # Restrict to one role template id, e.g. from an alert link.
    $RoleTemplateId = $Request.Query.roleTemplateId
    # Restrict to the roles one principal (object id) holds.
    $PrincipalId = $Request.Query.principalId

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $Counts = @(
                Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'RoleAssignmentScheduleInstances' -CountsOnly
                Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Roles' -CountsOnly
            ) | Where-Object { $_ }
            $RefreshedAt = @{}
            foreach ($Count in $Counts) {
                $Existing = $RefreshedAt[$Count.PartitionKey]
                if (-not $Existing -or $Count.Timestamp -gt $Existing) { $RefreshedAt[$Count.PartitionKey] = $Count.Timestamp }
            }
            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = @($RefreshedAt.Keys | Where-Object { $TenantList.defaultDomainName -contains $_ })

            $Rows = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    foreach ($Row in Get-CIPPPIMRoleAssignments -TenantFilter $Tenant -FromCache -IncludePolicy) {
                        $Row | Add-Member -NotePropertyName 'LastRefreshed' -NotePropertyValue $RefreshedAt[$Tenant] -Force
                        $Rows.Add($Row)
                    }
                } catch {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to read cached role assignments: $($_.Exception.Message)" -sev Warning
                }
            }
            $Rows = @($Rows)
        } else {
            # A single-principal read drops the catalogue rows: the caller wants the roles the
            # principal holds, not every role it does not.
            $Params = @{ TenantFilter = $TenantFilter; IncludePolicy = $true; IncludeUnassignedRoles = [string]::IsNullOrWhiteSpace($PrincipalId) }
            if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) { $Params.PrincipalId = $PrincipalId }
            if (-not [string]::IsNullOrWhiteSpace($RoleTemplateId)) { $Params.RoleDefinitionId = $RoleTemplateId }
            $Rows = @(Get-CIPPPIMRoleAssignments @Params)
        }

        if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) { $Rows = @($Rows | Where-Object { $_.PrincipalId -eq $PrincipalId }) }
        if (-not [string]::IsNullOrWhiteSpace($RoleTemplateId)) { $Rows = @($Rows | Where-Object { $_.RoleDefinitionId -eq $RoleTemplateId }) }

        $Grouped = @(
            foreach ($Group in ($Rows | Group-Object -Property Tenant, RoleDefinitionId)) {
                $GroupRows = @($Group.Group)
                $Meta = $GroupRows[0]
                # Catalogue rows (AssignmentType 'Unassigned') carry the role but no principal.
                $Assignments = @($GroupRows | Where-Object { $_.PrincipalId })
                $PermanentCount = @($Assignments | Where-Object { $_.AssignmentType -eq 'Permanent' }).Count
                $EligibleCount = @($Assignments | Where-Object { $_.AssignmentType -eq 'Eligible' }).Count
                $ActiveCount = @($Assignments | Where-Object { $_.AssignmentType -in @('Active', 'ActivatedFromEligible') }).Count
                [PSCustomObject]@{
                    Tenant              = $Meta.Tenant
                    RoleDefinitionId    = $Meta.RoleDefinitionId
                    RoleDisplayName     = $Meta.RoleDisplayName
                    RoleDescription     = $Meta.RoleDescription
                    RoleIsBuiltIn       = $Meta.RoleIsBuiltIn
                    IsPrivilegedRole    = $Meta.IsPrivilegedRole
                    PIMCapable          = $Meta.PIMCapable
                    PolicySummary       = $Meta.PolicySummary
                    PolicyBelowFloor    = $Meta.PolicyBelowFloor
                    MemberCount         = $Assignments.Count
                    PermanentCount      = $PermanentCount
                    EligibleCount       = $EligibleCount
                    ActiveCount         = $ActiveCount
                    IsAssigned          = ($Assignments.Count -gt 0)
                    HasPermanentMembers = ($PermanentCount -gt 0)
                    # camelCase like the original ListRoles members, so the Members cell formatter
                    # and its CSV/PDF export read them.
                    Members             = @($Assignments | ForEach-Object {
                            [PSCustomObject]@{
                                displayName       = $_.PrincipalDisplayName
                                userPrincipalName = $_.PrincipalUserPrincipalName
                                principalType     = $_.PrincipalType
                                assignmentType    = $_.AssignmentType
                                endDateTime       = $_.EndDateTime
                            }
                        })
                    Assignments         = @($Assignments)
                    LastRefreshed       = $Meta.LastRefreshed
                }
            }
        )
        $Results = @($Grouped | Sort-Object -Property Tenant, RoleDisplayName)

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list roles with PIM data: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Results = "Failed to list roles with PIM data for $TenantFilter. $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    }
}
