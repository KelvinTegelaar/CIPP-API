function Invoke-CippTestE8_Admin_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML2) - No privileged account is inactive for more than 45 days (ISM-1648)
    #>
    param($Tenant)

    $TestId = 'E8_Admin_05'
    $Name = 'No privileged account inactive for more than 45 days (ISM-1648)'

    try {
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Roles -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles or Users) not found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }

        $PrivRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        $PrivUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Role in @($Roles)) {
            $RoleTemplateId = if ($Role.roleTemplateId) { [string]$Role.roleTemplateId } elseif ($Role.RoletemplateId) { [string]$Role.RoletemplateId } else { $null }
            if ($RoleTemplateId) { [void]$PrivRoleIds.Add($RoleTemplateId) }
            foreach ($M in @($Role.members)) {
                if ($M.id) { [void]$PrivUserIds.Add([string]$M.id) }
            }
        }
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $PrivRoleIds.Contains([string]$A.roleDefinitionId)) {
                [void]$PrivUserIds.Add([string]$A.principalId)
            }
        }
        $PrivUsers = $Users | Where-Object { $PrivUserIds.Contains($_.id) -and $_.accountEnabled -eq $true }

        if (-not $PrivUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No enabled privileged users found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }

        $Threshold = (Get-Date).AddDays(-45)
        $Stale = foreach ($U in $PrivUsers) {
            $Last = $U.signInActivity.lastSignInDateTime
            if (-not $Last) { continue }
            $LastDt = [datetime]::Parse($Last)
            if ($LastDt -lt $Threshold) {
                [pscustomobject]@{ UPN = $U.userPrincipalName; LastSignIn = $LastDt.ToString('yyyy-MM-dd') }
            }
        }

        if (-not $Stale) {
            $Status = 'Passed'
            $Result = "All $($PrivUsers.Count) enabled privileged user(s) signed in within the last 45 days (or have no recorded sign-in)."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Stale.Count) of $($PrivUsers.Count) enabled privileged user(s) have not signed in for more than 45 days:`n`n| UPN | Last sign-in |`n| :-- | :----------- |`n")
            foreach ($S in ($Stale | Sort-Object LastSignIn | Select-Object -First 50)) {
                $null = $Sb.Append("| $($S.UPN) | $($S.LastSignIn) |`n")
            }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Restrict Admin Privileges'
    }
}
