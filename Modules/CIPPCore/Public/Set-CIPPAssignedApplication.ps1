function Set-CIPPAssignedApplication {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $ExcludeGroup,
        $ExcludeGroupIds,
        $ExcludeGroupNames,
        $Intent,
        $AppType,
        $ApplicationId,
        $TenantFilter,
        $GroupIds,
        $AssignmentMode = 'replace',
        $AssignmentDirection,
        $APIName = 'Assign Application',
        $Headers,
        $AssignmentFilterName,
        $AssignmentFilterType = 'include'
    )
    Write-Host "GroupName: $GroupName Intent: $Intent AppType: $AppType ApplicationId: $ApplicationId TenantFilter: $TenantFilter APIName: $APIName"
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
                $ErrorMessage = "No assignment filter found matching the name: $AssignmentFilterName. Application assigned without filter."
                Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -sev 'Warning' -tenant $TenantFilter
                Write-Host $ErrorMessage
            }
        }

        $assignmentSettings = $null
        if ($AppType) {
            $assignmentSettings = @{
                '@odata.type' = "#microsoft.graph.$($AppType)AppAssignmentSettings"
            }

            switch ($AppType) {
                'Win32Lob' {
                    $assignmentSettings.notifications = 'hideAll'
                }
                'WinGet' {
                    $assignmentSettings.notifications = 'hideAll'
                }
                'macOsVpp' {
                    $assignmentSettings.useDeviceLicensing = $true
                }
                'iosVpp' {
                    $assignmentSettings.useDeviceLicensing = $true
                }
                default {
                    # No additional settings
                }
            }
        }

        # Build the assignment object
        $MobileAppAssignment = switch ($GroupName) {
            'AllUsers' {
                @(@{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                        intent        = $Intent
                        settings      = $assignmentSettings
                    })
                break
            }
            'AllDevices' {
                @(@{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                        intent        = $Intent
                        settings      = $assignmentSettings
                    })
                break
            }
            'AllDevicesAndUsers' {
                @(
                    @{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                        intent        = $Intent
                        settings      = $assignmentSettings
                    },
                    @{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                        intent        = $Intent
                        settings      = $assignmentSettings
                    }
                )
            }
            default {
                $resolvedGroupIds = @()
                if ($PSBoundParameters.ContainsKey('GroupIds') -and $GroupIds) {
                    $resolvedGroupIds = $GroupIds
                } elseif ($GroupName) {
                    $GroupNames = $GroupName.Split(',')
                    $resolvedGroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName' -tenantid $TenantFilter | ForEach-Object {
                        $Group = $_
                        foreach ($SingleName in $GroupNames) {
                            if ($Group.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                                $Group.id
                            }
                        }
                    }
                    Write-Information "found $($resolvedGroupIds) groups"
                }

                # Only panic when an include target was actually requested. Exclude-only
                # assignments legitimately resolve to no include groups here.
                $IncludeRequested = $GroupName -or ($GroupIds -and @($GroupIds).Count -gt 0)
                if (-not $resolvedGroupIds -and $IncludeRequested) {
                    throw 'No matching groups resolved for assignment request.'
                }

                foreach ($Group in $resolvedGroupIds) {
                    @{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = @{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId       = $Group
                        }
                        intent        = $Intent
                        settings      = $assignmentSettings
                    }
                }
            }
        }

        # Normalize to an array so appending exclusions appends an element rather than
        # merging hashtable keys (a single include group makes the switch return a scalar).
        # Filter nulls so an exclude-only assignment doesn't carry an empty placeholder.
        $MobileAppAssignment = @($MobileAppAssignment | Where-Object { $_ })

        # Add exclusion group assignments
        if ($ExcludeGroup -or ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0)) {
            # Prefer explicit group IDs (from the picker); fall back to name resolution
            # for templates/wizards/API callers that still send ExcludeGroup names.
            if ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0) {
                Write-Host "Excluding group(s) by id from application assignment: $($ExcludeGroupIds -join ', ')"
                $ResolvedExcludeIds = @($ExcludeGroupIds)
            } else {
                Write-Host "Excluding group(s) from application assignment: $ExcludeGroup"
                $ExcludeGroupNames = $ExcludeGroup.Split(',').Trim()
                $ResolvedExcludeIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName' -tenantid $TenantFilter | ForEach-Object {
                    $Group = $_
                    foreach ($SingleName in $ExcludeGroupNames) {
                        if ($Group.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                            $Group.id
                        }
                    }
                }
            }

            foreach ($egid in $ResolvedExcludeIds) {
                # Graph rejects 'settings' on exclusion targets:
                # "Exclusion assignment does not support MobileAppAssignment Settings."
                $MobileAppAssignment += @{
                    '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                    target        = @{
                        '@odata.type' = '#microsoft.graph.exclusionGroupAssignmentTarget'
                        groupId       = $egid
                    }
                    intent        = $Intent
                }
            }
        }

        # Add assignment filter to each assignment if specified
        if ($ResolvedFilterId) {
            Write-Host "Adding assignment filter $ResolvedFilterId with type $AssignmentFilterType to assignments"
            foreach ($assignment in $MobileAppAssignment) {
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
                $ExistingAssignments = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($ApplicationId)/assignments" -tenantid $TenantFilter
            } catch {
                $ErrorMessage = "Unable to retrieve existing assignments for $ApplicationId. Existing assignments must be preserved for assignment mode '$AssignmentMode' and direction '$AssignmentDirection'. Aborting to avoid removing assignments. Error: $($_.Exception.Message)"
                Write-Warning $ErrorMessage
                throw $ErrorMessage
            }
        }

        # Decide which existing assignments to carry forward.
        $KeptAssignments = [System.Collections.Generic.List[object]]::new()
        if ($ExistingAssignments) {
            foreach ($ExistingAssignment in @($ExistingAssignments)) {
                $ExistingType = $ExistingAssignment.target.'@odata.type'
                $Keep = if ($AssignmentMode -eq 'replace' -and $DirectionScoped) {
                    # Direction-scoped replace: drop every target of the edited type, keep the rest
                    # (the other direction plus All Users / All Devices broad targets).
                    $ExistingType -ne $EditedType
                } else {
                    # Append: keep existing unless the new set overrides the same group/target.
                    switch ($ExistingType) {
                        '#microsoft.graph.groupAssignmentTarget' { $ExistingAssignment.target.groupId -notin $MobileAppAssignment.target.groupId }
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { $ExistingAssignment.target.groupId -notin $MobileAppAssignment.target.groupId }
                        default { $ExistingType -notin $MobileAppAssignment.target.'@odata.type' }
                    }
                }
                if ($Keep) {
                    $KeptAssignments.Add($ExistingAssignment)
                }
            }
        }

        $FinalAssignments = [System.Collections.Generic.List[object]]::new()
        if ($PreserveExisting) {
            # Rebuild each assignment, omitting 'settings' on exclusion targets (Graph rejects it).
            $AddAssignment = {
                param($a)
                $entry = @{
                    '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                    target        = $a.target
                    intent        = $a.intent
                }
                if ($a.target.'@odata.type' -ne '#microsoft.graph.exclusionGroupAssignmentTarget' -and $null -ne $a.settings) {
                    $entry.settings = $a.settings
                }
                $FinalAssignments.Add($entry)
            }

            $KeptAssignments | ForEach-Object { & $AddAssignment $_ }
            $MobileAppAssignment | ForEach-Object { & $AddAssignment $_ }
        } else {
            $FinalAssignments = $MobileAppAssignment
        }

        $DefaultAssignmentObject = [PSCustomObject]@{
            mobileAppAssignments = @(
                $FinalAssignments
            )
        }
        $ShouldProcess = $PSCmdlet.ShouldProcess($GroupName, "Assigning Application $ApplicationId")
        if ($ShouldProcess) {
            Start-Sleep -Seconds 1
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($ApplicationId)/assign" -tenantid $TenantFilter -type POST -body ($DefaultAssignmentObject | ConvertTo-Json -Compress -Depth 10)
        }

        $AssignedGroupsDisplay = if ($GroupName) {
            $GroupName
        } elseif ($GroupIds -and @($GroupIds).Count -gt 0) {
            @($GroupIds) -join ', '
        }

        $ExcludedGroupsDisplay = if ($ExcludeGroupNames -and @($ExcludeGroupNames).Count -gt 0) {
            @($ExcludeGroupNames) -join ', '
        } elseif ($ExcludeGroupIds -and @($ExcludeGroupIds).Count -gt 0) {
            @($ExcludeGroupIds) -join ', '
        } else {
            $ExcludeGroup
        }

        $ResultMessage = if ($ExcludedGroupsDisplay -and $AssignedGroupsDisplay) {
            "Assigned Application $ApplicationId to $AssignedGroupsDisplay excluding group '$ExcludedGroupsDisplay'"
        } elseif ($ExcludedGroupsDisplay) {
            "Updated exclusions for Application $ApplicationId to group '$ExcludedGroupsDisplay'"
        } elseif ($AssignmentDirection -eq 'exclude' -and $AssignmentMode -eq 'replace') {
            "Cleared exclusions for Application $ApplicationId"
        } else {
            "Assigned Application $ApplicationId to $AssignedGroupsDisplay"
        }

        if ($ShouldProcess) {
            Write-LogMessage -headers $Headers -API $APIName -message $ResultMessage -Sev 'Info' -tenant $TenantFilter
        }
        return $ResultMessage
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not assign application $ApplicationId to $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Could not assign application $ApplicationId to $GroupName. Error: $($ErrorMessage.NormalizedError)"
    }
}
