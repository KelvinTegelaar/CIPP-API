function Compare-CIPPIntuneAssignments {
    <#
    .SYNOPSIS
        Compares existing Intune policy assignments against expected assignment settings.
    .DESCRIPTION
        Returns $true if the existing assignments match the expected settings, $false if they differ,
        or $null if the comparison could not be completed (e.g. Graph error).
    .PARAMETER ExistingAssignments
        The current assignments on the policy, as returned by Get-CIPPIntunePolicyAssignments.
    .PARAMETER ExpectedAssignTo
        The expected assignment target type: allLicensedUsers, AllDevices, AllDevicesAndUsers,
        customGroup, or On (no assignment).
    .PARAMETER ExpectedCustomGroup
        The expected custom group name(s), comma-separated. Used when ExpectedAssignTo is 'customGroup'.
    .PARAMETER ExpectedExcludeGroup
        The expected exclusion group name(s), comma-separated.
    .PARAMETER ExpectedAssignmentFilter
        The expected assignment filter display name. Wildcards supported.
    .PARAMETER ExpectedAssignmentFilterType
        'include' or 'exclude'. Defaults to 'include'.
    .PARAMETER TenantFilter
        The tenant to query for group/filter resolution.
    .FUNCTIONALITY
        Internal
    #>
    param(
        [object[]]$ExistingAssignments,
        [string]$ExpectedAssignTo,
        [string]$ExpectedCustomGroup,
        [string]$ExpectedExcludeGroup,
        [string]$ExpectedAssignmentFilter,
        [string]$ExpectedAssignmentFilterType = 'include',
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        # Normalize existing targets
        $ExistingTargetTypes = @($ExistingAssignments.target.'@odata.type' | Where-Object { $_ })
        $ExistingIncludeGroupIds = @(
            $ExistingAssignments |
                Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' } |
                ForEach-Object { $_.target.groupId }
        )
        $ExistingExcludeGroupIds = @(
            $ExistingAssignments |
                Where-Object { $_.target.'@odata.type' -eq '#microsoft.graph.exclusionGroupAssignmentTarget' } |
                ForEach-Object { $_.target.groupId }
        )

        # Determine expected include target types
        $ExpectedIncludeTypes = switch ($ExpectedAssignTo) {
            'allLicensedUsers'   { @('#microsoft.graph.allLicensedUsersAssignmentTarget') }
            'AllDevices'         { @('#microsoft.graph.allDevicesAssignmentTarget') }
            'AllDevicesAndUsers' { @('#microsoft.graph.allDevicesAssignmentTarget', '#microsoft.graph.allLicensedUsersAssignmentTarget') }
            'customGroup'        { @('#microsoft.graph.groupAssignmentTarget') }
            'On'                 { @() }
            default              { @() }
        }

        # Compare include target types (ignore exclusion targets)
        $ExistingIncludeTypes = @($ExistingTargetTypes | Where-Object { $_ -ne '#microsoft.graph.exclusionGroupAssignmentTarget' })
        $TargetTypeMatch = $true
        foreach ($t in $ExpectedIncludeTypes) {
            if ($t -notin $ExistingIncludeTypes) { $TargetTypeMatch = $false; break }
        }
        if ($TargetTypeMatch) {
            foreach ($t in $ExistingIncludeTypes) {
                if ($t -notin $ExpectedIncludeTypes) { $TargetTypeMatch = $false; break }
            }
        }

        # Lazy-load groups cache only if needed
        $AllGroupsCache = $null

        # For custom groups, resolve names to IDs and compare
        $IncludeGroupMatch = $true
        if ($ExpectedAssignTo -eq 'customGroup' -and $ExpectedCustomGroup) {
            $AllGroupsCache = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter
            $ExpectedGroupIds = @(
                $ExpectedCustomGroup.Split(',').Trim() | ForEach-Object {
                    $name = $_
                    $AllGroupsCache | Where-Object { $_.displayName -like $name } | Select-Object -ExpandProperty id
                } | Where-Object { $_ }
            )
            $MissingIds = @($ExpectedGroupIds | Where-Object { $_ -notin $ExistingIncludeGroupIds })
            $ExtraIds   = @($ExistingIncludeGroupIds | Where-Object { $_ -notin $ExpectedGroupIds })
            $IncludeGroupMatch = ($MissingIds.Count -eq 0 -and $ExtraIds.Count -eq 0)
        }

        # Compare exclusion groups
        $ExcludeGroupMatch = $true
        if ($ExpectedExcludeGroup) {
            if (-not $AllGroupsCache) {
                $AllGroupsCache = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter
            }
            $ExpectedExcludeIds = @(
                $ExpectedExcludeGroup.Split(',').Trim() | ForEach-Object {
                    $name = $_
                    $AllGroupsCache | Where-Object { $_.displayName -like $name } | Select-Object -ExpandProperty id
                } | Where-Object { $_ }
            )
            $MissingExcludeIds = @($ExpectedExcludeIds | Where-Object { $_ -notin $ExistingExcludeGroupIds })
            $ExtraExcludeIds   = @($ExistingExcludeGroupIds | Where-Object { $_ -notin $ExpectedExcludeIds })
            $ExcludeGroupMatch = ($MissingExcludeIds.Count -eq 0 -and $ExtraExcludeIds.Count -eq 0)
        } elseif ($ExistingExcludeGroupIds.Count -gt 0) {
            # No exclusions expected but some exist
            $ExcludeGroupMatch = $false
        }

        # Compare assignment filter
        $FilterMatch = $true
        if ($ExpectedAssignmentFilter) {
            $ExistingFilterIds = @(
                $ExistingAssignments |
                    Where-Object { $_.target.deviceAndAppManagementAssignmentFilterId } |
                    ForEach-Object { $_.target.deviceAndAppManagementAssignmentFilterId }
            )
            if ($ExistingFilterIds.Count -eq 0) {
                $FilterMatch = $false
            } else {
                $AllFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
                $ExpectedFilter = $AllFilters | Where-Object { $_.displayName -like $ExpectedAssignmentFilter } | Select-Object -First 1
                $FilterMatch = $ExpectedFilter -and ($ExpectedFilter.id -in $ExistingFilterIds)
            }
        }

        return $TargetTypeMatch -and $IncludeGroupMatch -and $ExcludeGroupMatch -and $FilterMatch

    } catch {
        Write-Warning "Compare-CIPPIntuneAssignments failed for tenant $TenantFilter : $($_.Exception.Message)"
        return $null  # null = unknown, don't treat as mismatch
    }
}
