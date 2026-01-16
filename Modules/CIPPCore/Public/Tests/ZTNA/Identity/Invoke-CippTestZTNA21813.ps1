function Invoke-CippTestZTNA21813 {
    <#
    .SYNOPSIS
    High Global Administrator to privileged user ratio
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested
    $TestId = 'ZTNA21813'

    try {
        $GlobalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'

        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $RoleEligibilitySchedules = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        $AllGAUsers = @{}
        $AllPrivilegedUsers = @{}
        $UserRoleMap = @{}

        foreach ($Role in $PrivilegedRoles) {
            $ActiveAssignments = $RoleAssignmentScheduleInstances | Where-Object {
                $_.roleDefinitionId -eq $Role.templateId -and $_.assignmentType -eq 'Assigned'
            }
            $EligibleAssignments = $RoleEligibilitySchedules | Where-Object {
                $_.roleDefinitionId -eq $Role.templateId
            }

            $AllAssignments = @($ActiveAssignments) + @($EligibleAssignments)

            foreach ($Assignment in $AllAssignments) {
                $User = $Users | Where-Object { $_.id -eq $Assignment.principalId } | Select-Object -First 1
                if (-not $User) { continue }

                $UserId = $User.id
                $IsGARole = $Role.templateId -eq $GlobalAdminRoleId

                if ($IsGARole) {
                    $AllGAUsers[$UserId] = $User
                }

                if (-not $IsGARole) {
                    $AllPrivilegedUsers[$UserId] = $User
                }

                if (-not $UserRoleMap.ContainsKey($UserId)) {
                    $UserRoleMap[$UserId] = @{
                        User  = $User
                        Roles = [System.Collections.ArrayList]@()
                        IsGA  = $false
                    }
                }

                if ($Role.displayName -notin $UserRoleMap[$UserId].Roles) {
                    [void]$UserRoleMap[$UserId].Roles.Add($Role.displayName)
                }

                if ($IsGARole) {
                    $UserRoleMap[$UserId].IsGA = $true
                }
            }
        }

        $GARoleAssignmentCount = $AllGAUsers.Count
        $PrivilegedRoleAssignmentCount = $AllPrivilegedUsers.Count
        $TotalPrivilegedRoleAssignmentCount = $GARoleAssignmentCount + $PrivilegedRoleAssignmentCount

        if ($TotalPrivilegedRoleAssignmentCount -gt 0) {
            $GAPercentage = [math]::Round(($GARoleAssignmentCount / $TotalPrivilegedRoleAssignmentCount) * 100, 2)
            $OtherPercentage = [math]::Round(($PrivilegedRoleAssignmentCount / $TotalPrivilegedRoleAssignmentCount) * 100, 2)
        } else {
            $GAPercentage = 0
            $OtherPercentage = 0
        }

        $HasHealthyRatio = $false
        $HasModerateRatio = $false
        $HasHighRatio = $false
        $CustomStatus = $null

        if ($GAPercentage -lt 30) {
            $StatusIndicator = '✅ Passed'
            $HasHealthyRatio = $true
        } elseif ($GAPercentage -ge 30 -and $GAPercentage -lt 50) {
            $StatusIndicator = '⚠️ Investigate'
            $HasModerateRatio = $true
        } else {
            $StatusIndicator = '❌ Failed'
            $HasHighRatio = $true
        }

        $MdInfo = "`n## Privileged role assignment summary`n`n"
        $MdInfo += "**Global administrator role count:** $GARoleAssignmentCount ($GAPercentage%) - $StatusIndicator`n`n"
        $MdInfo += "**Other privileged role count:** $PrivilegedRoleAssignmentCount ($OtherPercentage%)`n`n"

        $MdInfo += "## User privileged role assignments`n`n"
        $MdInfo += "| User | Global administrator | Other Privileged Role(s) |`n"
        $MdInfo += "| :--- | :------------------- | :------ |`n"

        $SortedUsers = $UserRoleMap.Values | Sort-Object @{Expression = { -not $_.IsGA } }, @{Expression = { $_.User.displayName } }

        foreach ($UserEntry in $SortedUsers) {
            $User = $UserEntry.User
            $IsGA = if ($UserEntry.IsGA) { 'Yes' } else { 'No' }

            $OtherRoles = $UserEntry.Roles | Where-Object { $_ -ne 'Global Administrator' } | Sort-Object
            $RolesList = if ($OtherRoles.Count -gt 0) { ($OtherRoles -join ', ') } else { '-' }

            $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($User.id)/hidePreviewBanner~/true"
            $MdInfo += "| [$($User.displayName)]($UserLink) | $IsGA | $RolesList |`n"
        }

        if ($UserRoleMap.Count -eq 0) {
            $MdInfo += "| No privileged users found | - | - |`n"
        }

        if ($TotalPrivilegedRoleAssignmentCount -eq 0) {
            $Passed = $true
            $ResultMarkdown = "No privileged role assignments found in the tenant.$MdInfo"
        } elseif ($HasHealthyRatio) {
            $Passed = $true
            $ResultMarkdown = "Less than 30% of privileged role assignments in the tenant are Global Administrator.$MdInfo"
        } elseif ($HasModerateRatio) {
            $Passed = $false
            $CustomStatus = 'Investigate'
            $ResultMarkdown = "Between 30-50% of privileged role assignments in the tenant are Global Administrator.$MdInfo"
        } else {
            $Passed = $false
            $ResultMarkdown = "More than 50% of privileged role assignments in the tenant are Global Administrator.$MdInfo"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'High Global Administrator to privileged user ratio' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'High Global Administrator to privileged user ratio' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
    }
}
