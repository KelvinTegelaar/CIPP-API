function Set-CIPPAssignedPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $GroupName,
        $PolicyId,
        $Type,
        $TenantFilter,
        $PlatformType,
        $APIName = 'Assign Policy',
        $ExecutingUser
    )
    if (!$PlatformType) { $PlatformType = 'deviceManagement' }
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
                $GroupIds = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter | ForEach-Object {
                    $Group = $_
                    foreach ($SingleName in $GroupNames) {
                        if ($_.displayName -like $SingleName) {
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

        $AssignJSON = ($assignmentsObject | ConvertTo-Json -Depth 10 -Compress)
        Write-Host "AssignJSON: $AssignJSON"
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning policy $PolicyId")) {
            Write-Host "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign"
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$($PlatformType)/$Type('$($PolicyId)')/assign" -tenantid $tenantFilter -type POST -body $AssignJSON
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Assigned $GroupName to Policy $PolicyId" -Sev 'Info' -tenant $TenantFilter
        }
    } catch {
        #$ErrorMessage = Get-CippException -Exception $_
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to assign $GroupName to Policy $PolicyId, using Platform $PlatformType and $Type. The error is:$ErrorMessage" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
    }
}
