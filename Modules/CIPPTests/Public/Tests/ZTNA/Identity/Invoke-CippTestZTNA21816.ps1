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
        $RoleEligibilitySchedules = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'
        $Groups = Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups'

        $EligibleGAs = $RoleEligibilitySchedules.Where({ $_.roleDefinitionId -eq $GlobalAdminRoleId })
        $EligibleGAUsers = 0

        # Build id-keyed lookups once to avoid O(N*M) Where-Object scans
        $UsersById = @{}
        foreach ($U in $Users) { $UsersById[$U.id] = $U }
        $GroupsById = @{}
        foreach ($G in $Groups) { $GroupsById[$G.id] = $G }
        # Composite-key lookup: principalId|roleDefinitionId
        $AssignmentByPrincipalRole = @{}
        foreach ($A in $RoleAssignmentScheduleInstances) {
            $key = '{0}|{1}' -f $A.principalId, $A.roleDefinitionId
            if (-not $AssignmentByPrincipalRole.ContainsKey($key)) {
                $AssignmentByPrincipalRole[$key] = $A
            }
        }

        foreach ($EligibleGA in $EligibleGAs) {
            $Principal = $UsersById[$EligibleGA.principalId]
            if ($Principal) {
                $EligibleGAUsers++
            } else {
                $GroupPrincipal = $GroupsById[$EligibleGA.principalId]
                if ($GroupPrincipal -and $GroupPrincipal.members) {
                    $MemberSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$GroupPrincipal.members)
                    foreach ($U in $Users) { if ($MemberSet.Contains($U.id)) { $EligibleGAUsers++ } }
                }
            }
        }

        foreach ($Role in $PrivilegedRoles) {
            if ($Role.templateId -eq $GlobalAdminRoleId) { continue }

            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.RoletemplateId

            foreach ($Member in $RoleMembers) {
                $Assignment = $AssignmentByPrincipalRole['{0}|{1}' -f $Member.id, $Role.RoletemplateId]

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
            $Assignment = $AssignmentByPrincipalRole['{0}|{1}' -f $Member.id, $GlobalAdminRoleId]

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
                    $UserDetail = $UsersById[$Member.id]
                    if ($UserDetail) {
                        $MemberInfo.onPremisesSyncEnabled = $UserDetail.onPremisesSyncEnabled
                    }
                    $PermanentGAUserList.Add($MemberInfo)
                } elseif ($Member.'@odata.type' -eq '#microsoft.graph.group') {
                    $PermanentGAGroupList.Add($MemberInfo)

                    $Group = $GroupsById[$Member.id]
                    if ($Group -and $Group.members) {
                        $MemberSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Group.members)
                        foreach ($GroupMember in $Users) {
                            if (-not $MemberSet.Contains($GroupMember.id)) { continue }
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
            $ResultMarkdown = [System.Text.StringBuilder]::new('No eligible Global Administrator assignments found. PIM usage cannot be confirmed.')
        } elseif ($HasNonPIMPrivileged) {
            $Passed = $false
            $ResultMarkdown = [System.Text.StringBuilder]::new('Found Microsoft Entra privileged role assignments that are not managed with PIM.')
        } elseif ($PermanentGACount -gt 2) {
            $Passed = $false
            $CustomStatus = 'Investigate'
            $ResultMarkdown = [System.Text.StringBuilder]::new('Three or more accounts are permanently assigned the Global Administrator role. Review to determine whether these are emergency access accounts.')
        } else {
            $Passed = $true
            $ResultMarkdown = [System.Text.StringBuilder]::new('All Microsoft Entra privileged role assignments are managed with PIM with the exception of up to two standing Global Administrator accounts.')
        }

        $null = $ResultMarkdown.Append("`n`n## Assessment summary`n`n")
        $null = $ResultMarkdown.Append("| Metric | Count |`n")
        $null = $ResultMarkdown.Append("| :----- | :---- |`n")
        $null = $ResultMarkdown.Append("| Privileged roles found | $($PrivilegedRoles.Count) |`n")
        $null = $ResultMarkdown.Append("| Eligible Global Administrators | $EligibleGAUsers |`n")
        $null = $ResultMarkdown.Append("| Non-PIM privileged users | $($NonPIMPrivilegedUsers.Count) |`n")
        $null = $ResultMarkdown.Append("| Non-PIM privileged groups | $($NonPIMPrivilegedGroups.Count) |`n")
        $null = $ResultMarkdown.Append("| Permanent Global Administrator users | $($PermanentGAUserList.Count) |`n")

        if ($NonPIMPrivilegedUsers.Count -gt 0 -or $NonPIMPrivilegedGroups.Count -gt 0) {
            $null = $ResultMarkdown.Append("`n## Non-PIM managed privileged role assignments`n`n")
            $null = $ResultMarkdown.Append("| Display name | User principal name | Role name | Assignment type |`n")
            $null = $ResultMarkdown.Append("| :----------- | :------------------ | :-------- | :-------------- |`n")

            foreach ($User in $NonPIMPrivilegedUsers) {
                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($User.id)/hidePreviewBanner~/true"
                $null = $ResultMarkdown.Append("| [$($User.displayName)]($UserLink) | $($User.userPrincipalName) | $($User.roleName) | $($User.assignmentType) |`n")
            }

            foreach ($Group in $NonPIMPrivilegedGroups) {
                $GroupLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/RolesAndAdministrators/groupId/$($Group.id)/menuId/"
                $null = $ResultMarkdown.Append("| [$($Group.displayName)]($GroupLink) | N/A (Group) | $($Group.roleName) | $($Group.assignmentType) |`n")
            }
        }

        if ($PermanentGAUserList.Count -gt 0) {
            $null = $ResultMarkdown.Append("`n## Permanent Global Administrator assignments`n`n")
            $null = $ResultMarkdown.Append("| Display name | User principal name | Assignment type | On-Premises synced |`n")
            $null = $ResultMarkdown.Append("| :----------- | :------------------ | :-------------- | :----------------- |`n")

            foreach ($User in $PermanentGAUserList) {
                $SyncStatus = if ($null -ne $User.onPremisesSyncEnabled) { $User.onPremisesSyncEnabled } else { 'N/A' }
                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($User.id)/hidePreviewBanner~/true"
                $null = $ResultMarkdown.Append("| [$($User.displayName)]($UserLink) | $($User.userPrincipalName) | $($User.assignmentType) | $SyncStatus |`n")
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
