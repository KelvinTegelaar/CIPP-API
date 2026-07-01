function Set-CIPPAssignedPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $ExcludeGroup,
        $ExcludeGroupIds,
        $ExcludeGroupNames,
        $PolicyId,
        $Type,
        $TenantFilter,
        $PlatformType = 'deviceManagement',
        $APIName = 'Assign Policy',
        $Headers,
        $AssignmentFilterName,
        $AssignmentFilterType = 'include',
        $GroupIds,
        $GroupNames,
        $AssignmentMode = 'replace',
        $AssignmentDirection
    )

    Write-Host "Assigning policy $PolicyId ($PlatformType/$Type) to $GroupName"

    try {
        # Resolve assignment filter name to ID if provided
        $ResolvedFilterId = $null
        if ($AssignmentFilterName) {
            Write-Host "Looking up assignment filter by name: $AssignmentFilterName"
            $AllFilters = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -tenantid $TenantFilter
            $MatchingFilter = $AllFilters | Where-Object { $_.displayName -like $AssignmentFilterName } | Select-Object -First 1

            if ($MatchingFilter) {
                $ResolvedFilterId = $MatchingFilter.id
                Write-Host "Found assignment filter: $($MatchingFilter.displayName) with ID: $ResolvedFilterId"
            } else {
                $ErrorMessage = "No assignment filter found matching the name: $AssignmentFilterName. Policy assigned without filter."
                Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -sev 'Warning' -tenant $TenantFilter
                Write-Host $ErrorMessage
            }
        }

        $assignmentsList = [System.Collections.Generic.List[object]]::new()
        switch ($GroupName) {
            'allLicensedUsers' {
                $assignmentsList.Add(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                    }
                )
            }
            'AllDevices' {
                $assignmentsList.Add(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                    }
                )
            }
            'AllDevicesAndUsers' {
                $assignmentsList.Add(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                    }
                )
                $assignmentsList.Add(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                    }
                )
            }
            'On' {
                # Do not assign to any group - used to turn on policy without assignments
            }
            default {
                # Use GroupIds if provided, otherwise resolve by name
                $resolvedGroupIds = @()
                if ($GroupIds -and @($GroupIds).Count -gt 0) {
                    $resolvedGroupIds = @($GroupIds)
                    Write-Host "Using provided GroupIds: $($resolvedGroupIds -join ', ')"
                } elseif ($GroupName) {
                    $GroupNames = $GroupName.Split(',').Trim()
                    $resolvedGroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter |
                        ForEach-Object {
                            foreach ($SingleName in $GroupNames) {
                                if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                                    $_.id
                                }
                            }
                        }
                }

                # Only error when an include target was actually requested. Exclude-only
                # assignments legitimately resolve to no include groups here.
                $IncludeRequested = $GroupName -or ($GroupIds -and @($GroupIds).Count -gt 0)
                if ((-not $resolvedGroupIds -or $resolvedGroupIds.Count -eq 0) -and $IncludeRequested) {
                    $ErrorMessage = "No groups found matching the specified name(s): $GroupName. Policy not assigned."
                    Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -sev 'Warning' -tenant $TenantFilter
                    throw $ErrorMessage
                }

                foreach ($gid in $resolvedGroupIds) {
                    $assignmentsList.Add(
                        @{
                            target = @{
                                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                                groupId       = $gid
                            }
                        }
                    )
                }
            }
        }
        if ($ExcludeGroup -or ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0)) {
            # Prefer explicit group IDs (from the picker); fall back to name resolution
            # for templates/wizards/API callers that still send ExcludeGroup names.
            if ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0) {
                Write-Host "Excluding custom group(s) by id: $($ExcludeGroupIds -join ', ')"
                $ResolvedExcludeIds = @($ExcludeGroupIds)
            } else {
                Write-Host "We're supposed to exclude a custom group. The group is $ExcludeGroup"
                $ExcludeGroupNames = $ExcludeGroup.Split(',').Trim()
                $ResolvedExcludeIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter |
                    ForEach-Object {
                        foreach ($SingleName in $ExcludeGroupNames) {
                            if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                                $_.id
                            }
                        }
                    }
            }

            foreach ($egid in $ResolvedExcludeIds) {
                $assignmentsList.Add(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                            groupId       = $egid
                        }
                    }
                )
            }
        }

        # Add assignment filter to each assignment if specified
        if ($ResolvedFilterId) {
            Write-Host "Adding assignment filter $ResolvedFilterId with type $AssignmentFilterType to assignments"
            foreach ($assignment in $assignmentsList) {
                # Don't add filters to exclusion targets
                if ($assignment.target.'@odata.type' -ne '#microsoft.graph.exclusionGroupAssignmentTarget') {
                    $assignment.target.deviceAndAppManagementAssignmentFilterId = $ResolvedFilterId
                    $assignment.target.deviceAndAppManagementAssignmentFilterType = $AssignmentFilterType
                }
            }
        }

        # Determine which existing assignments (if any) must be preserved.
        #   append              -> keep all existing (minus ones the new set overrides)
        #   replace + direction -> keep everything except the direction being edited
        #                          (Custom Group action only; legacy replace overwrites everything)
        $DirectionScoped = -not [string]::IsNullOrWhiteSpace($AssignmentDirection)
        $EditedType = switch ($AssignmentDirection) {
            'exclude' { '#microsoft.graph.exclusionGroupAssignmentTarget' }
            'include' { '#microsoft.graph.groupAssignmentTarget' }
            default { $null }
        }
        $PreserveExisting = ($AssignmentMode -eq 'append') -or ($AssignmentMode -eq 'replace' -and $DirectionScoped)

        $ExistingAssignments = @()
        if ($PreserveExisting) {
            try {
                $uri = "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assignments"
                $ExistingAssignments = New-GraphGetRequest -uri $uri -tenantid $TenantFilter
                Write-Host "Found $($ExistingAssignments.Count) existing assignments for policy $PolicyId"
            } catch {
                $ErrorMessage = "Unable to retrieve existing assignments for $PolicyId. Existing assignments must be preserved for assignment mode '$AssignmentMode' and direction '$AssignmentDirection'. Aborting to avoid removing assignments. Error: $($_.Exception.Message)"
                Write-Warning $ErrorMessage
                throw $ErrorMessage
            }
        }

        # Decide which existing assignments to carry forward.
        $FinalAssignments = [System.Collections.Generic.List[object]]::new()
        if ($ExistingAssignments -and $ExistingAssignments.Count -gt 0) {
            foreach ($ExistingAssignment in $ExistingAssignments) {
                $ExistingType = $ExistingAssignment.target.'@odata.type'
                $Keep = if ($AssignmentMode -eq 'replace' -and $DirectionScoped) {
                    # Direction-scoped replace: drop every target of the edited type, keep the rest
                    # (the other direction plus All Users / All Devices broad targets).
                    $ExistingType -ne $EditedType
                } else {
                    # Append: keep existing unless the new set overrides the same group/target.
                    switch ($ExistingType) {
                        '#microsoft.graph.groupAssignmentTarget' { $ExistingAssignment.target.groupId -notin $assignmentsList.target.groupId }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { $ExistingAssignment.target.groupId -notin $assignmentsList.target.groupId }
                        default { $ExistingType -notin $assignmentsList.target.'@odata.type' }
                    }
                }
                if ($Keep) {
                    $FinalAssignments.Add(@{ target = $ExistingAssignment.target })
                }
            }
        }

        foreach ($newAssignment in $assignmentsList) {
            $FinalAssignments.Add($newAssignment)
        }

        # Determine the assignment property name based on type
        $AssignmentPropertyName = switch ($Type) {
            'deviceHealthScripts' { 'deviceHealthScriptAssignments' }
            'deviceManagementScripts' { 'deviceManagementScriptAssignments' }
            'deviceShellScripts' { 'deviceManagementScriptAssignments' }
            default { 'assignments' }
        }

        $assignmentsObject = @{ $AssignmentPropertyName = @($FinalAssignments) }

        $AssignJSON = ConvertTo-Json -InputObject $assignmentsObject -Depth 10 -Compress
        $ShouldProcess = $PSCmdlet.ShouldProcess($GroupName, "Assigning policy $PolicyId")
        if ($ShouldProcess) {
            $uri = "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign"
            $null = New-GraphPOSTRequest -uri $uri -tenantid $TenantFilter -type POST -body $AssignJSON

            # Build a friendly display name for the assigned groups
            $AssignedGroupsDisplay = if ($GroupNames -and @($GroupNames).Count -gt 0) {
                ($GroupNames -join ', ')
            } elseif ($GroupName) {
                $GroupName
            } elseif ($GroupIds -and @($GroupIds).Count -gt 0) {
                @($GroupIds) -join ', '
            } else {
                $null
            }

            $ExcludedGroupsDisplay = if ($ExcludeGroupNames -and @($ExcludeGroupNames).Count -gt 0) {
                ($ExcludeGroupNames -join ', ')
            } elseif ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0) {
                ($ExcludeGroupIds -join ', ')
            } else {
                $ExcludeGroup
            }

            $ResultMessage = if ($ExcludedGroupsDisplay -and $AssignedGroupsDisplay) {
                "Successfully assigned group '$AssignedGroupsDisplay' and excluded group '$ExcludedGroupsDisplay' on Policy $PolicyId"
            } elseif ($ExcludedGroupsDisplay) {
                "Successfully updated exclusions to group '$ExcludedGroupsDisplay' on Policy $PolicyId"
            } elseif ($AssignmentDirection -eq 'exclude' -and $AssignmentMode -eq 'replace') {
                "Successfully cleared exclusions on Policy $PolicyId"
            } else {
                "Successfully assigned group '$AssignedGroupsDisplay' on Policy $PolicyId"
            }

            if ($ShouldProcess) {
                Write-LogMessage -headers $Headers -API $APIName -message $ResultMessage -Sev 'Info' -tenant $TenantFilter
            }
            return $ResultMessage
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to assign $GroupName to Policy $PolicyId, using Platform $PlatformType and $Type. The error is:$($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Failed to assign $GroupName to Policy $PolicyId. Error: $ErrorMessage"
    }
}
