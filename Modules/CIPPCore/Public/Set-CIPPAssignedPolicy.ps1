function Set-CIPPAssignedPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $ExcludeGroup,
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
        $AssignmentMode = 'replace'
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
                Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -Sev 'Warning' -tenant $TenantFilter
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
                                if ($_.displayName -like $SingleName) {
                                    $_.id
                                }
                            }
                        }
                }

                if (-not $resolvedGroupIds -or $resolvedGroupIds.Count -eq 0) {
                    $ErrorMessage = "No groups found matching the specified name(s): $GroupName. Policy not assigned."
                    Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -Sev 'Warning' -tenant $TenantFilter
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
        if ($ExcludeGroup) {
            Write-Host "We're supposed to exclude a custom group. The group is $ExcludeGroup"
            $ExcludeGroupNames = $ExcludeGroup.Split(',').Trim()
            $ExcludeGroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter |
                ForEach-Object {
                    foreach ($SingleName in $ExcludeGroupNames) {
                        if ($_.displayName -like $SingleName) {
                            $_.id
                        }
                    }
                }

            foreach ($egid in $ExcludeGroupIds) {
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

        # If we're appending, we need to get existing assignments
        $ExistingAssignments = @()
        if ($AssignmentMode -eq 'append') {
            try {
                $uri = "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assignments"
                $ExistingAssignments = New-GraphGetRequest -uri $uri -tenantid $TenantFilter
                Write-Host "Found $($ExistingAssignments.Count) existing assignments for policy $PolicyId"
            } catch {
                Write-Warning "Unable to retrieve existing assignments for $PolicyId. Proceeding with new assignments only. Error: $($_.Exception.Message)"
                $ExistingAssignments = @()
            }
        }

        # Deduplicate current assignments so the new ones override existing ones
        if ($ExistingAssignments -and $ExistingAssignments.Count -gt 0) {
            $ExistingAssignments = $ExistingAssignments | ForEach-Object {
                $ExistingAssignment = $_
                switch ($ExistingAssignment.target.'@odata.type') {
                    '#microsoft.graph.groupAssignmentTarget' {
                        if ($ExistingAssignment.target.groupId -notin $assignmentsList.target.groupId) {
                            $ExistingAssignment
                        }
                    }
                    '#microsoft.graph.exclusionGroupAssignmentTarget' {
                        if ($ExistingAssignment.target.groupId -notin $assignmentsList.target.groupId) {
                            $ExistingAssignment
                        }
                    }
                    default {
                        if ($ExistingAssignment.target.'@odata.type' -notin $assignmentsList.target.'@odata.type') {
                            $ExistingAssignment
                        }
                    }
                }
            }
        }

        # Build final assignments list
        $FinalAssignments = [System.Collections.Generic.List[object]]::new()
        if ($AssignmentMode -eq 'append' -and $ExistingAssignments) {
            foreach ($existing in $ExistingAssignments) {
                $FinalAssignments.Add(@{
                        target = $existing.target
                    })
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
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning policy $PolicyId")) {
            $uri = "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign"
            $null = New-GraphPOSTRequest -uri $uri -tenantid $TenantFilter -type POST -body $AssignJSON

            # Build a friendly display name for the assigned groups
            $AssignedGroupsDisplay = if ($GroupNames -and @($GroupNames).Count -gt 0) {
                ($GroupNames -join ', ')
            } elseif ($GroupName) {
                $GroupName
            } else {
                'specified groups'
            }

            if ($ExcludeGroup) {
                Write-LogMessage -headers $Headers -API $APIName -message "Assigned group '$AssignedGroupsDisplay' and excluded group '$ExcludeGroup' on Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
                return "Successfully assigned group '$AssignedGroupsDisplay' and excluded group '$ExcludeGroup' on Policy $PolicyId"
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Assigned group '$AssignedGroupsDisplay' on Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
                return "Successfully assigned group '$AssignedGroupsDisplay' on Policy $PolicyId"
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to assign $GroupName to Policy $PolicyId, using Platform $PlatformType and $Type. The error is:$($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Failed to assign $GroupName to Policy $PolicyId. Error: $ErrorMessage"
    }
}
