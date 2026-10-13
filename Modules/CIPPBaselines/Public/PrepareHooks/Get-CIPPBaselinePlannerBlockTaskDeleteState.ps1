function Get-CIPPBaselinePlannerBlockTaskDeleteState {
    <#
    .SYNOPSIS
        Prepare hook for PlannerBlockTaskDelete: in-scope Planner users whose UserPolicy does not
        block deleting tasks they did not create.
    .DESCRIPTION
        Candidates are the PlannerUserPolicies cache rows (enabled members with an enabled
        Microsoft Planner service plan), narrowed by the include/exclude group names (resolved
        against the Groups cache, expanded to transitive user members in one batched read). An
        unresolved group name or a failed membership lookup returns No Data rather than grading a
        partial scope. A user with no policy yet counts as an offender.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @((New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'PlannerUserPolicies').Where({ $_ }))
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'PlannerUserPolicies')) { return @{ Current = $null; NoDataReason = 'the Planner user policies cache could not be collected for this tenant' } }

    $ToNames = {
        param($Value)
        @(@($Value) | ForEach-Object {
                if ($_ -is [string]) { $_ } else { "$($_.value ?? $_.label)" }
            } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    $IncludeNames = & $ToNames $Item.Variables.includeGroups
    $ExcludeNames = & $ToNames $Item.Variables.excludeGroups

    $IncludedIds = @{}
    $ExcludedIds = @{}
    if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
        $GroupIdsByName = @{}
        foreach ($Group in @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')) {
            $Name = "$($Group.displayName)".Trim()
            if (-not $Name -or -not $Group.id) { continue }
            if (-not $GroupIdsByName.ContainsKey($Name)) { $GroupIdsByName[$Name] = [System.Collections.Generic.List[string]]::new() }
            $GroupIdsByName[$Name].Add("$($Group.id)")
        }
        $Unresolved = @(foreach ($Name in @($IncludeNames) + @($ExcludeNames)) { if (-not $GroupIdsByName.ContainsKey($Name)) { $Name } })
        if ($Unresolved.Count -gt 0) {
            Write-Information "Baselines: PlannerBlockTaskDelete on $TenantFilter cannot resolve group(s) $($Unresolved -join ', ') - refusing to grade a partial scope."
            return @{ Current = $null; NoDataReason = "group(s) $($Unresolved -join ', ') could not be found, so the scope cannot be graded"; ConfigError = $true }
        }

        $Requests = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Scope in @(@{ Prefix = 'include'; Names = $IncludeNames }, @{ Prefix = 'exclude'; Names = $ExcludeNames })) {
            foreach ($Name in $Scope.Names) {
                foreach ($GroupId in $GroupIdsByName[$Name]) {
                    $Requests.Add(@{ id = "$($Scope.Prefix)-$GroupId"; method = 'GET'; url = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999" })
                }
            }
        }
        try {
            $Responses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true -Version 'v1.0')
        } catch {
            Write-Information "Baselines: PlannerBlockTaskDelete group membership lookup on $TenantFilter failed: $($_.Exception.Message)"
            return @{ Current = $null; NoDataReason = "the group membership lookup failed: $($_.Exception.Message)" }
        }
        foreach ($Response in $Responses) {
            if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                Write-Information "Baselines: PlannerBlockTaskDelete group membership lookup on $TenantFilter returned $($Response.status) for $($Response.id)."
                return @{ Current = $null; NoDataReason = "the group membership lookup returned $($Response.status) for $($Response.id)" }
            }
            $Bucket = if ("$($Response.id)".StartsWith('include-')) { $IncludedIds } else { $ExcludedIds }
            foreach ($Member in @($Response.body.value)) { if ($Member.id) { $Bucket["$($Member.id)"] = $true } }
        }
    }

    $Offenders = [System.Collections.Generic.List[string]]::new()
    $Targets = [System.Collections.Generic.List[object]]::new()
    foreach ($Policy in $Policies) {
        if ($IncludeNames.Count -gt 0 -and -not $IncludedIds.ContainsKey("$($Policy.id)")) { continue }
        if ($ExcludeNames.Count -gt 0 -and $ExcludedIds.ContainsKey("$($Policy.id)")) { continue }
        if ($Policy.blockDeleteTasksNotCreatedBySelf -eq $true) { continue }
        $Offenders.Add("$($Policy.userPrincipalName)")
        $Targets.Add([PSCustomObject]@{ userPrincipalName = "$($Policy.userPrincipalName)" })
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offenders | Sort-Object)
            targets   = @($Targets)
        }
    }
}
