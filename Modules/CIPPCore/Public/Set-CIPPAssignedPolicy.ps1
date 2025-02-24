function Set-CIPPAssignedPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $excludeGroup,
        $PolicyId,
        $Type,
        $TenantFilter,
        $PlatformType,
        $APIName = 'Assign Policy',
        $Headers
    )
    if (!$PlatformType) {
        $PlatformType = 'deviceManagement'
    }

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
                Write-Host "We're supposed to assign a custom group. The group is $GroupName"
                $GroupNames = $GroupName.Split(',')
                $GroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter |
                ForEach-Object {
                    foreach ($SingleName in $GroupNames) {
                        if ($_.displayName -like $SingleName) {
                            $_.id
                        }
                    }
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
        if ($excludeGroup) {
            $ExcludeGroupNames = $excludeGroup.Split(',')
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
        Write-Host "AssignJSON: $AssignJSON"
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning policy $PolicyId")) {
            Write-Host "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign"
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign" -tenantid $TenantFilter -type POST -body $AssignJSON
            Write-LogMessage -headers $Headers -API $APIName -message "Assigned $GroupName and excluded $excludeGroup to Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to assign $GroupName to Policy $PolicyId, using Platform $PlatformType and $Type. The error is:$ErrorMessage" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
    }
}
