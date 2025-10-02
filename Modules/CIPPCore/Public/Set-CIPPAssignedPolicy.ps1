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
        $Headers
    )

    Write-Host "Assigning policy $PolicyId ($PlatformType/$Type) to $GroupName"

    try {
        $assignmentsList = New-Object System.Collections.Generic.List[System.Object]
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
                $GroupNames = $GroupName.Split(',').Trim()
                $GroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter |
                    ForEach-Object {
                        foreach ($SingleName in $GroupNames) {
                            if ($_.displayName -like $SingleName) {
                                $_.id
                            }
                        }
                    }
                
                if (-not $GroupIds -or $GroupIds.Count -eq 0) {
                    $ErrorMessage = "No groups found matching the specified name(s): $GroupName. Policy not assigned."
                    Write-LogMessage -headers $Headers -API $APIName -message $ErrorMessage -Sev 'Warning' -tenant $TenantFilter
                    return $ErrorMessage
                }
                
                foreach ($gid in $GroupIds) {
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

        $assignmentsObject = [PSCustomObject]@{
            assignments = $assignmentsList
        }

        $AssignJSON = $assignmentsObject | ConvertTo-Json -Depth 10 -Compress
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning policy $PolicyId")) {
            $uri = "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign"
            $null = New-GraphPOSTRequest -uri $uri -tenantid $TenantFilter -type POST -body $AssignJSON
            if ($ExcludeGroup) {
                Write-LogMessage -headers $Headers -API $APIName -message "Assigned group '$GroupName' and excluded group '$ExcludeGroup' on Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
                return "Successfully assigned group '$GroupName' and excluded group '$ExcludeGroup' on Policy $PolicyId"
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "Assigned group '$GroupName' on Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
                return "Successfully assigned group '$GroupName' on Policy $PolicyId"
            }
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to assign $GroupName to Policy $PolicyId, using Platform $PlatformType and $Type. The error is:$ErrorMessage" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Failed to assign $GroupName to Policy $PolicyId. Error: $ErrorMessage"
    }
}
