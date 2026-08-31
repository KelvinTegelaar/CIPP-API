function Invoke-ListRoleAssignments {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .SYNOPSIS
        List Entra directory role assignments with their PIM assignment type.
    .DESCRIPTION
        Returns one row per principal, role and scope showing whether the assignment is Permanent (active with no end date), Active (time-bound), ActivatedFromEligible or Eligible, whether it is held directly or through a role-assignable group, the scope (directory or administrative unit), the principal type, the role's description and built-in flag, and the role's PIM policy summary. For a single tenant roles that nobody holds are included as Unassigned rows so the result is also the role catalogue. A single tenant is read live from Graph (Entra ID P2 tenants via PIM, others via unified RBAC where every assignment is permanent); AllTenants is served from the reporting cache.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    # Restrict to one principal (object id), e.g. for the user view page.
    $PrincipalId = $Request.Query.principalId
    # Restrict to one role template id.
    $RoleTemplateId = $Request.Query.roleTemplateId
    # Only return permanent (active, no end date) assignments.
    $PermanentOnly = [bool]($Request.Query.permanentOnly -eq $true -or "$($Request.Query.permanentOnly)" -eq 'true')
    # Single tenant: also list roles that nobody holds (AssignmentType 'Unassigned'), so the result is the full role catalogue. Default true; set to false for assignments only.
    $IncludeUnassigned = -not ("$($Request.Query.includeUnassigned)" -eq 'false')

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

            $Results = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $Rows = Get-CIPPPIMRoleAssignments -TenantFilter $Tenant -FromCache -IncludePolicy
                    foreach ($Row in $Rows) {
                        $Row | Add-Member -NotePropertyName 'LastRefreshed' -NotePropertyValue $RefreshedAt[$Tenant] -Force
                        $Results.Add($Row)
                    }
                } catch {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to read cached role assignments: $($_.Exception.Message)" -sev Warning
                }
            }
            $Results = @($Results)
        } else {
            $Params = @{ TenantFilter = $TenantFilter; IncludePolicy = $true; IncludeUnassignedRoles = ($IncludeUnassigned -and -not $PermanentOnly) }
            if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) { $Params.PrincipalId = $PrincipalId }
            if (-not [string]::IsNullOrWhiteSpace($RoleTemplateId)) { $Params.RoleDefinitionId = $RoleTemplateId }
            $Results = @(Get-CIPPPIMRoleAssignments @Params)
        }

        if (-not [string]::IsNullOrWhiteSpace($PrincipalId)) { $Results = @($Results | Where-Object { $_.PrincipalId -eq $PrincipalId }) }
        if (-not [string]::IsNullOrWhiteSpace($RoleTemplateId)) { $Results = @($Results | Where-Object { $_.RoleDefinitionId -eq $RoleTemplateId }) }
        if ($PermanentOnly) { $Results = @($Results | Where-Object { $_.AssignmentType -eq 'Permanent' }) }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list role assignments: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Results = "Failed to list role assignments for $TenantFilter. $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($Results)
    }
}
