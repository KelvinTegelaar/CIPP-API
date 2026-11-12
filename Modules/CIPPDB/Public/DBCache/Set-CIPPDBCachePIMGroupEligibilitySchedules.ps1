function Set-CIPPDBCachePIMGroupEligibilitySchedules {
    <#
    .SYNOPSIS
        Caches PIM for Groups eligibility for the tenant's role-assignable groups

    .DESCRIPTION
        Keeps one row per eligibility: who can activate membership or ownership of a role-assignable group, the
        only groups that can hold a directory role. eligibleUsers lists the users behind the row: the principal
        itself, or the users inside an eligible group, nested ones included. A failed read writes nothing and
        rethrows.

    .PARAMETER TenantFilter
        The tenant to cache PIM for Groups eligibility for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching PIM for Groups eligibility schedules' -sev Debug

        $ReadBulk = {
            param($Requests, $AsApp)
            foreach ($Response in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $AsApp -Version 'v1.0')) {
                if (($Response.status -as [int]) -ge 400 -or $Response.PagingIncomplete) {
                    throw "Request for $($Response.id) failed: $($Response.body.error.message ?? $Response.PagingError ?? $Response.status)"
                }
                $Response
            }
        }

        $Groups = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/groups?$filter=isAssignableToRole eq true&$select=id,displayName&$top=999' -tenantid $TenantFilter)
        $Schedules = [System.Collections.Generic.List[object]]::new()
        $GroupNames = @{}

        if ($Groups.Count -gt 0) {
            # Graph only lists eligibility per group, and only the application holds the PIM for Groups permission
            $Requests = foreach ($Group in $Groups) {
                $GroupNames[[string]$Group.id] = $Group.displayName
                [PSCustomObject]@{
                    id     = [string]$Group.id
                    method = 'GET'
                    url    = "/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=groupId eq '$($Group.id)'&`$expand=principal"
                }
            }
            foreach ($Response in (& $ReadBulk $Requests $true)) {
                foreach ($Schedule in $Response.body.value) { $Schedules.Add($Schedule) }
            }
        }

        $UsersByGroupId = @{}
        $PrincipalGroupIds = @($Schedules | Where-Object { $_.principal.'@odata.type' -eq '#microsoft.graph.group' } | ForEach-Object { [string]$_.principalId } | Sort-Object -Unique)
        if ($PrincipalGroupIds.Count -gt 0) {
            $Requests = foreach ($Id in $PrincipalGroupIds) {
                $UsersByGroupId[$Id] = @()
                [PSCustomObject]@{
                    id     = $Id
                    method = 'GET'
                    url    = "/groups/$Id/transitiveMembers/microsoft.graph.user?`$select=id,displayName,userPrincipalName&`$top=999"
                }
            }
            foreach ($Response in (& $ReadBulk $Requests $false)) {
                $UsersByGroupId[[string]$Response.id] = @($Response.body.value | Select-Object id, displayName, userPrincipalName)
            }
        }

        foreach ($Schedule in $Schedules) {
            $PrincipalType = $Schedule.principal.'@odata.type'
            $EligibleUsers = @(
                if ($PrincipalType -eq '#microsoft.graph.group') { $UsersByGroupId[[string]$Schedule.principalId] }
                elseif ($PrincipalType -eq '#microsoft.graph.user') { $Schedule.principal | Select-Object id, displayName, userPrincipalName }
            )
            $Schedule | Add-Member -Force -NotePropertyMembers @{
                groupDisplayName = $GroupNames[[string]$Schedule.groupId]
                eligibleUsers    = $EligibleUsers
            }
        }

        if ($Schedules.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMGroupEligibilitySchedules' -Data $Schedules.ToArray() -AddCount
        } else {
            # Read successfully with no eligibility: record the empty set so tests know the groups were checked.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PIMGroupEligibilitySchedules' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Schedules.Count) PIM for Groups eligibility schedules" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache PIM for Groups eligibility schedules: $($_.Exception.Message)" -sev Error
        # Rethrow so Invoke-CIPPDBCacheCollection counts the type as failed rather than leaving an old count row looking current.
        throw
    }
}
