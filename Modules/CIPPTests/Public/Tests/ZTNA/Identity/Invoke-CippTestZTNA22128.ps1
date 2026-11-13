function Invoke-CippTestZTNA22128 {
    <#
    .SYNOPSIS
    Guests are not assigned high privileged directory roles
    #>
    param($Tenant)
    #Tested
    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $Guests = Get-CIPPTestData -TenantFilter $Tenant -Type 'Guests'

        if (-not $Roles -or (-not $Guests -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'Guests' -CountsOnly))) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $GuestIdHash = @{}
        foreach ($Guest in $Guests) {
            $GuestIdHash[$Guest.id] = $Guest
        }

        $PrivilegedRoleTemplateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $RoleNamesById = @{}
        foreach ($Role in (Get-CIPPPrivilegedRoleTemplateIds -WithNames)) {
            [void]$PrivilegedRoleTemplateIds.Add($Role.Id)
            $RoleNamesById[$Role.Id] = $Role.DisplayName
        }

        $GuestsInPrivilegedRoles = [System.Collections.Generic.List[object]]::new()
        if ($GuestIdHash.Count -gt 0) {
            foreach ($Role in $Roles) {
                if (-not $PrivilegedRoleTemplateIds.Contains([string]$Role.roleTemplateId)) { continue }
                foreach ($Member in $Role.members) {
                    if ($GuestIdHash.ContainsKey($Member.id)) {
                        $GuestsInPrivilegedRoles.Add([PSCustomObject]@{
                                RoleName       = $Role.displayName
                                GuestId        = $Member.id
                                DisplayName    = $GuestIdHash[$Member.id].displayName
                                UPN            = $GuestIdHash[$Member.id].userPrincipalName
                                AssignmentType = 'Active'
                            })
                    }
                }
            }

            $Now = [datetimeoffset]::UtcNow
            foreach ($Eligibility in (Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules')) {
                if (-not $GuestIdHash.ContainsKey($Eligibility.principalId) -or -not $PrivilegedRoleTemplateIds.Contains([string]$Eligibility.roleDefinitionId)) { continue }
                $EndDateTime = $Eligibility.scheduleInfo.expiration.endDateTime
                if ($EndDateTime -and [datetimeoffset]$EndDateTime -lt $Now) { continue }
                $GuestsInPrivilegedRoles.Add([PSCustomObject]@{
                        RoleName       = $RoleNamesById[[string]$Eligibility.roleDefinitionId]
                        GuestId        = $Eligibility.principalId
                        DisplayName    = $GuestIdHash[$Eligibility.principalId].displayName
                        UPN            = $GuestIdHash[$Eligibility.principalId].userPrincipalName
                        AssignmentType = 'Eligible'
                    })
            }
        }

        if ($GuestsInPrivilegedRoles.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Passed' -ResultMarkdown "Guests with privileged roles were not found.`n`nAll users with privileged roles are members of the tenant." -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $Result = [System.Text.StringBuilder]::new("Guests with privileged roles were detected.`n`n## Guests with privileged roles`n`n")
        $null = $Result.Append("| Role name | User name | User principal name | Assignment type |`n")
        $null = $Result.Append("| :-------- | :-------- | :------------------ | :-------------- |`n")
        foreach ($Assignment in $GuestsInPrivilegedRoles) {
            $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($Assignment.GuestId)/hidePreviewBanner~/true"
            $null = $Result.Append("| $($Assignment.RoleName) | [$($Assignment.DisplayName)]($PortalLink) | $($Assignment.UPN) | $($Assignment.AssignmentType) |`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Failed' -ResultMarkdown $Result.ToString() -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA22128' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Guests are not assigned high privileged directory roles' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
