function Set-CIPPAssignedPolicy {
    [CmdletBinding()]
    param(
        $GroupName,
        $PolicyId,
        $Type,
        $TenantFilter,
        $APIName = 'Assign Policy',
        $ExecutingUser
    )

    try { 
        $assignmentsObject = switch ($GroupName) {
            'allLicensedUsers' {
                @(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                    }
                )
                break 
            }
            'AllDevices' {
                @(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                    }
                )
                break 
            }
            'AllDevicesAndUsers' { 
                @(
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                    },
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                    }
                )
            }
            default {
                $GroupNames = $GroupName.Split(',')
                $GroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter | ForEach-Object { 
                    $Group = $_
                    foreach ($SingleName in $GroupNames) {
                        if ($_.displayname -like $SingleName) {
                            $group.id
                        }
                    }
                }
                foreach ($Group in $GroupIds) {
                    @{
                        target = @{
                            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                            groupId       = $Group
                        }
                    }
                }
            }
        }
        $assignmentsObject = [PSCustomObject]@{
            assignments = @($assignmentsObject)
        }
        $assign = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$Type('$($PolicyId)')/assign" -tenantid $tenantFilter -type POST -body ($assignmentsObject | ConvertTo-Json -Depth 10)
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Assigned Policy to $($GroupName)" -Sev 'Info' -tenant $TenantFilter
        return "Assigned policy to $($GroupName)"
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to assign Policy to $GroupName" -Sev 'Error' -tenant $TenantFilter
        return "Could not assign policy to $GroupName. Error: $($_.Exception.Message)"
    }
}
