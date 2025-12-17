function Set-CIPPAssignedApplication {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $Intent,
        $AppType,
        $ApplicationId,
        $TenantFilter,
        $GroupIds,
        $AssignmentMode = 'replace',
        $APIName = 'Assign Application',
        $Headers
    )
    Write-Host "GroupName: $GroupName Intent: $Intent AppType: $AppType ApplicationId: $ApplicationId TenantFilter: $TenantFilter APIName: $APIName"
    try {
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
                } else {
                    $GroupNames = $GroupName.Split(',')
                    $resolvedGroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter | ForEach-Object {
                        $Group = $_
                        foreach ($SingleName in $GroupNames) {
                            if ($_.displayName -like $SingleName) {
                                $group.id
                            }
                        }
                    }
                    Write-Information "found $($resolvedGroupIds) groups"
                }

                # We ain't found nothing so we panic
                if (-not $resolvedGroupIds) {
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

        # If we're appending, we need to get existing assignments
        if ($AssignmentMode -eq 'append') {
            try {
                $ExistingAssignments = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($ApplicationId)/assignments" -tenantid $TenantFilter
            } catch {
                Write-Warning "Unable to retrieve existing assignments for $ApplicationId. Proceeding with new assignments only. Error: $($_.Exception.Message)"
                $ExistingAssignments = @()
            }
        }

        # Deduplicate current assignments so the new ones override existing ones
        if ($ExistingAssignments) {
            $ExistingAssignments = $ExistingAssignments | ForEach-Object {
                $ExistingAssignment = $_
                switch ($ExistingAssignment.target.'@odata.type') {
                    '#microsoft.graph.groupAssignmentTarget' {
                        if ($ExistingAssignment.target.groupId -notin $MobileAppAssignment.target.groupId) {
                            $ExistingAssignment
                        }
                    }
                    default {
                        if ($ExistingAssignment.target.'@odata.type' -notin $MobileAppAssignment.target.'@odata.type') {
                            $ExistingAssignment
                        }
                    }
                }
            }
        }

        $FinalAssignments = [System.Collections.Generic.List[object]]::new()
        if ($AssignmentMode -eq 'append' -and $ExistingAssignments) {
            $ExistingAssignments | ForEach-Object {
                $FinalAssignments.Add(@{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = $_.target
                        intent        = $_.intent
                        settings      = $_.settings
                    })
            }

            $MobileAppAssignment | ForEach-Object {
                $FinalAssignments.Add(@{
                        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                        target        = $_.target
                        intent        = $_.intent
                        settings      = $_.settings
                    })
            }
        } else {
            $FinalAssignments = $MobileAppAssignment
        }

        $DefaultAssignmentObject = [PSCustomObject]@{
            mobileAppAssignments = @(
                $FinalAssignments
            )
        }
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning Application $ApplicationId")) {
            Start-Sleep -Seconds 1
            # Write-Information (ConvertTo-Json $DefaultAssignmentObject -Depth 10)
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($ApplicationId)/assign" -tenantid $TenantFilter -type POST -body ($DefaultAssignmentObject | ConvertTo-Json -Compress -Depth 10)
            Write-LogMessage -headers $Headers -API $APIName -message "Assigned Application $ApplicationId to $($GroupName)" -Sev 'Info' -tenant $TenantFilter
        }
        return "Assigned Application $ApplicationId to $($GroupName)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not assign application $ApplicationId to $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Could not assign application $ApplicationId to $GroupName. Error: $($ErrorMessage.NormalizedError)"
    }
}
