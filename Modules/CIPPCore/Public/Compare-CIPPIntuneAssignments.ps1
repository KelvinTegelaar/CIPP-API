function Compare-CIPPIntuneAssignments {
    <#
    .SYNOPSIS
        Compares existing Intune policy assignments against a standard's expected assignment settings.
    .DESCRIPTION
        Returns a result object saying whether the assignments match and, when they do not, exactly
        which include groups, exclusion groups or filters differ. The detail is the point: a bare
        boolean gives an operator nothing to act on, which is how "assignments differ" deviations
        end up unexplainable when the assignment in the portal looks correct.

        The verdict is scoped to what remediation actually manages, via Get-CIPPIntuneAssignTarget:

        - Include targets and groups are only asserted when the standard names a target (Managed).
          With AssignTo unset or 'Do not assign', Set-CIPPIntunePolicy adds no include target, so
          demanding a particular set of them produces a deviation no run can clear.
        - Exclusion groups and filters that the standard specifies are asserted whenever remediation
          touches assignments at all (Applied).
        - Extra include groups, extra exclusions and unexpected filters are only asserted when the
          standard owns the assignments (Managed), because that is the only case where remediation
          replaces rather than appends and can therefore remove them.

        Group names are resolved to ids the same way Set-CIPPAssignedPolicy resolves them, so the
        two agree on which groups a wildcard covers. A name that matches nothing is reported rather
        than silently dropped - a renamed group is a common cause of a policy that looks correctly
        assigned but no longer matches the standard.
    .PARAMETER ExistingAssignments
        The current assignments on the policy, as returned by Get-CIPPIntunePolicyAssignments.
    .PARAMETER ExpectedAssignTo
        The expected assignment target: allLicensedUsers, AllDevices, AllDevicesAndUsers,
        customGroup, or On (no include target). Accepts the { label, value } shape.
    .PARAMETER ExpectedCustomGroup
        The expected custom group name(s), comma-separated. Used when ExpectedAssignTo is 'customGroup'.
        Wildcards supported.
    .PARAMETER ExpectedExcludeGroup
        The expected exclusion group name(s), comma-separated. Wildcards supported.
    .PARAMETER ExpectedAssignmentFilter
        The expected assignment filter display name. Wildcards supported.
    .PARAMETER ExpectedAssignmentFilterType
        'include' or 'exclude'. Defaults to 'include'.
    .PARAMETER PolicyType
        The policy's type, so the broad targets are read the same way remediation writes them. App
        Protection expresses "all users" as a group assignment rather than an allLicensedUsers
        target; without this the comparison would demand a target remediation never writes.
    .PARAMETER TenantFilter
        The tenant to query for group/filter resolution.
    .OUTPUTS
        PSCustomObject with:
            Matched              - $true or $false, or $null when the comparison could not be completed
            Unknown              - $true when the comparison could not be completed
            Managed / Applied    - see Get-CIPPIntuneAssignTarget
            MissingIncludeGroups - groups the standard expects that the policy is not assigned to
            ExtraIncludeGroups   - groups the policy is assigned to that the standard does not expect
            MissingExcludeGroups / ExtraExcludeGroups - the same for exclusions
            UnresolvedGroups     - configured group names that matched no group in the tenant
            Reasons              - one readable line per difference
    .FUNCTIONALITY
        Internal
    #>
    param(
        [object[]]$ExistingAssignments,
        $ExpectedAssignTo,
        [string]$ExpectedCustomGroup,
        [string]$ExpectedExcludeGroup,
        [string]$ExpectedAssignmentFilter,
        [string]$ExpectedAssignmentFilterType = 'include',
        [string]$PolicyType,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $GroupType = '#microsoft.graph.groupAssignmentTarget'
    $ExclusionType = '#microsoft.graph.exclusionGroupAssignmentTarget'
    $GroupUri = 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999'
    # Graph returns the empty GUID rather than null for "no filter" on some assignment shapes.
    $NoFilterId = '00000000-0000-0000-0000-000000000000'

    $ToGroupRefs = {
        param($Ids, $NameMap)
        @(foreach ($Id in $Ids) {
                [PSCustomObject]@{ id = $Id; displayName = $NameMap[$Id] }
            })
    }

    $Target = Get-CIPPIntuneAssignTarget -AssignTo $ExpectedAssignTo
    $Reasons = [System.Collections.Generic.List[string]]::new()

    try {
        $Assignments = @($ExistingAssignments | Where-Object { $_ })

        $ExistingIncludeAssignments = @($Assignments | Where-Object { $_.target.'@odata.type' -ne $ExclusionType })
        $ExistingIncludeTypes = @($ExistingIncludeAssignments.target.'@odata.type' | Where-Object { $_ })
        $ExistingIncludeGroupIds = @(
            $Assignments |
                Where-Object { $_.target.'@odata.type' -eq $GroupType } |
                ForEach-Object { $_.target.groupId }
        )
        $ExistingExcludeGroupIds = @(
            $Assignments |
                Where-Object { $_.target.'@odata.type' -eq $ExclusionType } |
                ForEach-Object { $_.target.groupId }
        )

        # Read the broad targets through the same helper remediation writes them with, so a policy
        # type that expresses one of them differently is expected the way it is actually applied.
        $BroadTarget = Get-CIPPIntuneAssignmentTarget -AssignTo $Target.AssignTo -PolicyType $PolicyType
        $ExpectedIncludeTypes = if ($Target.AssignTo -eq 'customGroup') {
            @($GroupType)
        } else {
            @($BroadTarget.Targets | ForEach-Object { $_.'@odata.type' })
        }
        # A broad target expressed as a group assignment (App Protection's "all users") is an
        # expected group, not an unexpected extra one.
        $BroadGroupIds = @($BroadTarget.Targets | Where-Object { $_.groupId } | ForEach-Object { $_.groupId })

        # Groups are looked up once and reused for name->id resolution and for naming the ids that
        # turn out to differ.
        $AllGroupsCache = $null
        $ResolveGroupNames = {
            param($NameList)
            $Ids = [System.Collections.Generic.List[string]]::new()
            $Unresolved = [System.Collections.Generic.List[string]]::new()
            foreach ($Name in @($NameList.Split(',').Trim() | Where-Object { $_ })) {
                # Square brackets are wildcard character classes to -like; group names containing
                # them are literal. Matches the escaping Set-CIPPAssignedPolicy applies.
                $Pattern = $Name -replace '\[', '`[' -replace '\]', '`]'
                $Matched = @($AllGroupsCache | Where-Object { $_.displayName -like $Pattern } | Select-Object -ExpandProperty id)
                if ($Matched.Count -eq 0) { $Unresolved.Add($Name) } else { $Ids.AddRange([string[]]$Matched) }
            }
            [PSCustomObject]@{ Ids = @($Ids); Unresolved = @($Unresolved) }
        }

        # Exclusions are only resolved when remediation would apply them; otherwise an unresolvable
        # name would be reported as a difference that nothing can act on.
        $CheckExcludeGroups = [bool]($ExpectedExcludeGroup -and $Target.Applied)
        $NeedsGroupLookup = ($Target.AssignTo -eq 'customGroup' -and $ExpectedCustomGroup) -or $CheckExcludeGroups
        if ($NeedsGroupLookup) {
            $AllGroupsCache = New-GraphGetRequest -uri $GroupUri -tenantid $TenantFilter
        }

        # -- include targets -------------------------------------------------------------------
        # Group targets are reported by id below, so only the broad All Users / All Devices targets
        # are compared at type level here.
        $TargetTypeMatch = $true
        if ($Target.Managed) {
            $MissingTypes = @($ExpectedIncludeTypes | Where-Object { $_ -ne $GroupType -and $_ -notin $ExistingIncludeTypes })
            $ExtraTypes = @($ExistingIncludeTypes | Where-Object { $_ -ne $GroupType -and $_ -notin $ExpectedIncludeTypes })
            if ($MissingTypes.Count -gt 0) {
                $TargetTypeMatch = $false
                $Reasons.Add("Policy is not assigned to $(($MissingTypes -replace '#microsoft\.graph\.', '') -join ', ')")
            }
            if ($ExtraTypes.Count -gt 0) {
                $TargetTypeMatch = $false
                $Reasons.Add("Policy is assigned to $(($ExtraTypes -replace '#microsoft\.graph\.', '') -join ', '), which the standard does not expect")
            }
        }

        # -- include groups --------------------------------------------------------------------
        $ExpectedGroupIds = @()
        $UnresolvedGroups = [System.Collections.Generic.List[string]]::new()
        if ($Target.AssignTo -eq 'customGroup' -and $ExpectedCustomGroup) {
            $Resolved = & $ResolveGroupNames $ExpectedCustomGroup
            $ExpectedGroupIds = $Resolved.Ids
            foreach ($Name in $Resolved.Unresolved) { $UnresolvedGroups.Add($Name) }
        }
        $ExpectedGroupIds = @($ExpectedGroupIds) + $BroadGroupIds
        $MissingIncludeIds = @($ExpectedGroupIds | Where-Object { $_ -notin $ExistingIncludeGroupIds })
        $ExtraIncludeIds = if ($Target.Managed) {
            @($ExistingIncludeGroupIds | Where-Object { $_ -notin $ExpectedGroupIds })
        } else { @() }

        # -- exclusion groups ------------------------------------------------------------------
        $ExpectedExcludeIds = @()
        if ($CheckExcludeGroups) {
            $Resolved = & $ResolveGroupNames $ExpectedExcludeGroup
            $ExpectedExcludeIds = $Resolved.Ids
            foreach ($Name in $Resolved.Unresolved) { $UnresolvedGroups.Add($Name) }
        }
        $MissingExcludeIds = @($ExpectedExcludeIds | Where-Object { $_ -notin $ExistingExcludeGroupIds })
        $ExtraExcludeIds = if ($Target.Managed) {
            @($ExistingExcludeGroupIds | Where-Object { $_ -notin $ExpectedExcludeIds })
        } else { @() }

        # -- assignment filter -----------------------------------------------------------------
        $ExistingFilterIds = @(
            $Assignments |
                Where-Object { $_.target.deviceAndAppManagementAssignmentFilterId -and $_.target.deviceAndAppManagementAssignmentFilterId -ne $NoFilterId } |
                ForEach-Object { $_.target.deviceAndAppManagementAssignmentFilterId }
        )
        $FilterMatch = $true
        if ($ExpectedAssignmentFilter -and $Target.Applied) {
            $AllFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
            $ExpectedFilter = $AllFilters | Where-Object { $_.displayName -like $ExpectedAssignmentFilter } | Select-Object -First 1
            if (-not $ExpectedFilter) {
                $FilterMatch = $false
                $Reasons.Add("Assignment filter '$ExpectedAssignmentFilter' does not exist in this tenant")
            } elseif ($ExistingIncludeAssignments.Count -gt 0) {
                # Remediation stamps the filter onto every include target, so anything short of that
                # is a difference. When there are no include targets at all the missing-assignment
                # reasons above already say so; adding a filter complaint on top is just noise.
                $ExpectedFilterType = if ($ExpectedAssignmentFilterType) { $ExpectedAssignmentFilterType } else { 'include' }
                $Unfiltered = @($ExistingIncludeAssignments | Where-Object { $_.target.deviceAndAppManagementAssignmentFilterId -ne $ExpectedFilter.id })
                $WrongMode = @($ExistingIncludeAssignments | Where-Object { $_.target.deviceAndAppManagementAssignmentFilterId -eq $ExpectedFilter.id -and $_.target.deviceAndAppManagementAssignmentFilterType -ne $ExpectedFilterType })
                if ($Unfiltered.Count -gt 0) {
                    $FilterMatch = $false
                    $Reasons.Add("Assignment filter '$($ExpectedFilter.displayName)' is not applied to every assignment target")
                }
                if ($WrongMode.Count -gt 0) {
                    $FilterMatch = $false
                    $Reasons.Add("Assignment filter '$($ExpectedFilter.displayName)' should be in '$ExpectedFilterType' mode")
                }
            }
        } elseif ($Target.Managed -and -not $ExpectedAssignmentFilter -and $ExistingFilterIds.Count -gt 0) {
            $FilterMatch = $false
            $Reasons.Add('An assignment filter is applied to this policy but the standard does not specify one')
        }

        # -- name the ids that differ ------------------------------------------------------------
        $DifferingIds = @($MissingIncludeIds + $ExtraIncludeIds + $MissingExcludeIds + $ExtraExcludeIds | Where-Object { $_ } | Select-Object -Unique)
        if ($DifferingIds.Count -gt 0 -and -not $AllGroupsCache) {
            $AllGroupsCache = New-GraphGetRequest -uri $GroupUri -tenantid $TenantFilter
        }
        $GroupNameById = @{}
        foreach ($Group in $AllGroupsCache) { $GroupNameById[$Group.id] = $Group.displayName }
        # Virtual groups are not in the directory, so name them from the helper that produced them.
        foreach ($Id in $BroadTarget.GroupNames.Keys) { $GroupNameById[$Id] = $BroadTarget.GroupNames[$Id] }
        $Describe = { param($Ids) (@(foreach ($Id in $Ids) { if ($GroupNameById[$Id]) { $GroupNameById[$Id] } else { $Id } }) -join ', ') }

        if ($MissingIncludeIds.Count -gt 0) { $Reasons.Add("Not assigned to expected group(s): $(& $Describe $MissingIncludeIds)") }
        if ($ExtraIncludeIds.Count -gt 0) { $Reasons.Add("Assigned to unexpected group(s): $(& $Describe $ExtraIncludeIds)") }
        if ($MissingExcludeIds.Count -gt 0) { $Reasons.Add("Missing exclusion for group(s): $(& $Describe $MissingExcludeIds)") }
        if ($ExtraExcludeIds.Count -gt 0) { $Reasons.Add("Unexpected exclusion for group(s): $(& $Describe $ExtraExcludeIds)") }
        foreach ($Name in $UnresolvedGroups) { $Reasons.Add("Group name '$Name' matches no group in this tenant") }

        $IncludeGroupMatch = ($MissingIncludeIds.Count -eq 0 -and $ExtraIncludeIds.Count -eq 0)
        $ExcludeGroupMatch = ($MissingExcludeIds.Count -eq 0 -and $ExtraExcludeIds.Count -eq 0)
        # A group name that resolves to nothing is a broken expectation, not a match.
        $GroupsResolved = ($UnresolvedGroups.Count -eq 0)

        return [PSCustomObject]@{
            Matched              = ($TargetTypeMatch -and $IncludeGroupMatch -and $ExcludeGroupMatch -and $FilterMatch -and $GroupsResolved)
            Unknown              = $false
            Managed              = $Target.Managed
            Applied              = $Target.Applied
            AssignTo             = $Target.AssignTo
            MissingIncludeGroups = & $ToGroupRefs $MissingIncludeIds $GroupNameById
            ExtraIncludeGroups   = & $ToGroupRefs $ExtraIncludeIds $GroupNameById
            MissingExcludeGroups = & $ToGroupRefs $MissingExcludeIds $GroupNameById
            ExtraExcludeGroups   = & $ToGroupRefs $ExtraExcludeIds $GroupNameById
            UnresolvedGroups     = @($UnresolvedGroups)
            Reasons              = @($Reasons)
            Error                = $null
        }

    } catch {
        # Unknown, not a mismatch. The caller must not record this as a deviation - a transient
        # Graph failure would otherwise write drift that no remediation run can clear.
        Write-Warning "Compare-CIPPIntuneAssignments failed for tenant $TenantFilter : $($_.Exception.Message)"
        return [PSCustomObject]@{
            Matched              = $null
            Unknown              = $true
            Managed              = $Target.Managed
            Applied              = $Target.Applied
            AssignTo             = $Target.AssignTo
            MissingIncludeGroups = @()
            ExtraIncludeGroups   = @()
            MissingExcludeGroups = @()
            ExtraExcludeGroups   = @()
            UnresolvedGroups     = @()
            Reasons              = @()
            Error                = $_.Exception.Message
        }
    }
}
