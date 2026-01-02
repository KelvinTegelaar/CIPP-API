function Invoke-CippTestZTNA21816 {
    <#
    .SYNOPSIS
    All Microsoft Entra privileged role assignments are managed with PIM
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested
    $TestId = 'ZTNA21816'

    try {
        $GlobalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'
        $PermanentGAUserList = [System.Collections.Generic.List[object]]::new()
        $PermanentGAGroupList = [System.Collections.Generic.List[object]]::new()
        $NonPIMPrivilegedUsers = [System.Collections.Generic.List[object]]::new()
        $NonPIMPrivilegedGroups = [System.Collections.Generic.List[object]]::new()

        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleEligibilitySchedules = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'
        $RoleAssignmentScheduleInstances = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'
        $Groups = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Groups'

        $EligibleGAs = $RoleEligibilitySchedules | Where-Object { $_.roleDefinitionId -eq $GlobalAdminRoleId }
        $EligibleGAUsers = 0

        foreach ($EligibleGA in $EligibleGAs) {
            $Principal = $Users | Where-Object { $_.id -eq $EligibleGA.principalId } | Select-Object -First 1
            if ($Principal) {
                $EligibleGAUsers++
            } else {
                $GroupPrincipal = $Groups | Where-Object { $_.id -eq $EligibleGA.principalId } | Select-Object -First 1
                if ($GroupPrincipal) {
                    $GroupMembers = $Users | Where-Object { $_.id -in $GroupPrincipal.members }
                    $EligibleGAUsers = $EligibleGAUsers + $GroupMembers.Count
                }
            }
        }

        foreach ($Role in $PrivilegedRoles) {
            if ($Role.templateId -eq $GlobalAdminRoleId) { continue }

            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.RoletemplateId

            foreach ($Member in $RoleMembers) {
                $Assignment = $RoleAssignmentScheduleInstances | Where-Object {
                    $_.principalId -eq $Member.id -and $_.roleDefinitionId -eq $Role.RoletemplateId
                } | Select-Object -First 1

                if (-not $Assignment -or ($Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime)) {
                    $MemberInfo = [PSCustomObject]@{
                        displayName       = $Member.displayName
                        userPrincipalName = $Member.userPrincipalName
                        id                = $Member.id
                        roleTemplateId    = $Role.RoletemplateId
                        roleName          = $Role.displayName
                        assignmentType    = if ($Assignment) { $Assignment.assignmentType } else { 'Not in PIM' }
                    }

                    if ($Member.'@odata.type' -eq '#microsoft.graph.user') {
                        $NonPIMPrivilegedUsers.Add($MemberInfo)
                    } else {
                        $NonPIMPrivilegedGroups.Add($MemberInfo)
                    }
                }
            }
        }

        $GAMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $GlobalAdminRoleId

        foreach ($Member in $GAMembers) {
            $Assignment = $RoleAssignmentScheduleInstances | Where-Object {
                $_.principalId -eq $Member.id -and $_.roleDefinitionId -eq $GlobalAdminRoleId
            } | Select-Object -First 1

            if (-not $Assignment -or ($Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime)) {
                $MemberInfo = [PSCustomObject]@{
                    displayName           = $Member.displayName
                    userPrincipalName     = $Member.userPrincipalName
                    id                    = $Member.id
                    roleTemplateId        = $GlobalAdminRoleId
                    roleName              = 'Global Administrator'
                    assignmentType        = if ($Assignment) { $Assignment.assignmentType } else { 'Not in PIM' }
                    onPremisesSyncEnabled = $null
                }

                if ($Member.'@odata.type' -eq '#microsoft.graph.user') {
                    $UserDetail = $Users | Where-Object { $_.id -eq $Member.id } | Select-Object -First 1
                    if ($UserDetail) {
                        $MemberInfo.onPremisesSyncEnabled = $UserDetail.onPremisesSyncEnabled
                    }
                    $PermanentGAUserList.Add($MemberInfo)
                } elseif ($Member.'@odata.type' -eq '#microsoft.graph.group') {
                    $PermanentGAGroupList.Add($MemberInfo)

                    $Group = $Groups | Where-Object { $_.id -eq $Member.id } | Select-Object -First 1
                    if ($Group) {
                        $GroupMembers = $Users | Where-Object { $_.id -in $Group.members }
                        foreach ($GroupMember in $GroupMembers) {
                            $GroupMemberInfo = [PSCustomObject]@{
                                displayName           = $GroupMember.displayName
                                userPrincipalName     = $GroupMember.userPrincipalName
                                id                    = $GroupMember.id
                                roleTemplateId        = $GlobalAdminRoleId
                                roleName              = 'Global Administrator (via group)'
                                assignmentType        = 'Via Group'
                                onPremisesSyncEnabled = $GroupMember.onPremisesSyncEnabled
                            }
                            $PermanentGAUserList.Add($GroupMemberInfo)
                        }
                    }
                }
            }
        }

        $HasPIMUsage = $EligibleGAUsers -gt 0
        $HasNonPIMPrivileged = ($NonPIMPrivilegedUsers.Count + $NonPIMPrivilegedGroups.Count) -gt 0
        $PermanentGACount = $PermanentGAUserList.Count
        $CustomStatus = $null

        if (-not $HasPIMUsage) {
            $Passed = $false
            $ResultMarkdown = 'No eligible Global Administrator assignments found. PIM usage cannot be confirmed.'
        } elseif ($HasNonPIMPrivileged) {
            $Passed = $false
            $ResultMarkdown = 'Found Microsoft Entra privileged role assignments that are not managed with PIM.'
        } elseif ($PermanentGACount -gt 2) {
            $Passed = $false
            $CustomStatus = 'Investigate'
            $ResultMarkdown = 'Three or more accounts are permanently assigned the Global Administrator role. Review to determine whether these are emergency access accounts.'
        } else {
            $Passed = $true
            $ResultMarkdown = 'All Microsoft Entra privileged role assignments are managed with PIM with the exception of up to two standing Global Administrator accounts.'
        }

        $ResultMarkdown += "`n`n## Assessment summary`n`n"
        $ResultMarkdown += "| Metric | Count |`n"
        $ResultMarkdown += "| :----- | :---- |`n"
        $ResultMarkdown += "| Privileged roles found | $($PrivilegedRoles.Count) |`n"
        $ResultMarkdown += "| Eligible Global Administrators | $EligibleGAUsers |`n"
        $ResultMarkdown += "| Non-PIM privileged users | $($NonPIMPrivilegedUsers.Count) |`n"
        $ResultMarkdown += "| Non-PIM privileged groups | $($NonPIMPrivilegedGroups.Count) |`n"
        $ResultMarkdown += "| Permanent Global Administrator users | $($PermanentGAUserList.Count) |`n"

        if ($NonPIMPrivilegedUsers.Count -gt 0 -or $NonPIMPrivilegedGroups.Count -gt 0) {
            $ResultMarkdown += "`n## Non-PIM managed privileged role assignments`n`n"
            $ResultMarkdown += "| Display name | User principal name | Role name | Assignment type |`n"
            $ResultMarkdown += "| :----------- | :------------------ | :-------- | :-------------- |`n"

            foreach ($User in $NonPIMPrivilegedUsers) {
                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($User.id)/hidePreviewBanner~/true"
                $ResultMarkdown += "| [$($User.displayName)]($UserLink) | $($User.userPrincipalName) | $($User.roleName) | $($User.assignmentType) |`n"
            }

            foreach ($Group in $NonPIMPrivilegedGroups) {
                $GroupLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/RolesAndAdministrators/groupId/$($Group.id)/menuId/"
                $ResultMarkdown += "| [$($Group.displayName)]($GroupLink) | N/A (Group) | $($Group.roleName) | $($Group.assignmentType) |`n"
            }
        }

        if ($PermanentGAUserList.Count -gt 0) {
            $ResultMarkdown += "`n## Permanent Global Administrator assignments`n`n"
            $ResultMarkdown += "| Display name | User principal name | Assignment type | On-Premises synced |`n"
            $ResultMarkdown += "| :----------- | :------------------ | :-------------- | :----------------- |`n"

            foreach ($User in $PermanentGAUserList) {
                $SyncStatus = if ($null -ne $User.onPremisesSyncEnabled) { $User.onPremisesSyncEnabled } else { 'N/A' }
                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($User.id)/hidePreviewBanner~/true"
                $ResultMarkdown += "| [$($User.displayName)]($UserLink) | $($User.userPrincipalName) | $($User.assignmentType) | $SyncStatus |`n"
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'All Microsoft Entra privileged role assignments are managed with PIM' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All Microsoft Entra privileged role assignments are managed with PIM' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'
    }
}
