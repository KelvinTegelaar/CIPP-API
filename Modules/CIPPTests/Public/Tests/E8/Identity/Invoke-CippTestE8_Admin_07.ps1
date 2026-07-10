function Invoke-CippTestE8_Admin_07 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Restrict Admin Privileges, ML2) - Break-glass accounts exist and are excluded from MFA enforcement
    #>
    param($Tenant)

    $TestId = 'E8_Admin_07'
    $Name = 'Break-glass accounts (2-4) exist and are excluded from at least one MFA Conditional Access policy'

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignmentScheduleInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $Roles -or -not $Users -or -not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles, Users or ConditionalAccessPolicies) not found.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }

        $GaRole = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1
        if (-not $GaRole) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Global Administrator role not found in the Roles cache.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }

        $GaTemplateId = if ($GaRole.roleTemplateId) { [string]$GaRole.roleTemplateId } elseif ($GaRole.RoletemplateId) { [string]$GaRole.RoletemplateId } else { $null }

        $GaUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($M in @($GaRole.members)) {
            if ($M.id) { [void]$GaUserIds.Add([string]$M.id) }
        }
        # RoleAssignmentScheduleInstances.roleDefinitionId is a role template ID, not the directory role instance ID.
        foreach ($A in @($RoleAssignmentScheduleInstances)) {
            if ($A.assignmentType -eq 'Assigned' -and $null -eq $A.endDateTime -and $A.principalId -and $GaTemplateId -and [string]$A.roleDefinitionId -eq $GaTemplateId) {
                [void]$GaUserIds.Add([string]$A.principalId)
            }
        }
        $GaUsers = $Users | Where-Object { $GaUserIds.Contains($_.id) }
        $BreakGlass = $GaUsers | Where-Object { $_.userPrincipalName -like '*onmicrosoft.com' -and $_.accountEnabled -eq $true }

        if (-not $BreakGlass -or $BreakGlass.Count -lt 2) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Only $($BreakGlass.Count) Global Administrator(s) on the *.onmicrosoft.com domain. ACSC guidance recommends 2-4 dedicated cloud-only break-glass accounts." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }
        if ($BreakGlass.Count -gt 4) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "$($BreakGlass.Count) cloud-only Global Administrators exist. Excessive break-glass accounts increase risk; reduce to 2-4." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
            return
        }

        $BreakGlassIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$BreakGlass.id)
        $MfaPolicies = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            (($_.grantControls.builtInControls -contains 'mfa') -or $_.grantControls.authenticationStrength)
        }
        $WithExclusion = foreach ($P in $MfaPolicies) {
            $Excluded = $P.conditions.users.excludeUsers
            if ($Excluded -and (@($Excluded) | Where-Object { $BreakGlassIds.Contains($_) }).Count -gt 0) { $P }
        }

        if ($WithExclusion) {
            $Status = 'Passed'
            $Result = "$($BreakGlass.Count) break-glass account(s) found. They are excluded from $((@($WithExclusion)).Count) MFA-enforcing Conditional Access policy/policies."
        } else {
            $Status = 'Failed'
            $Result = "$($BreakGlass.Count) break-glass account(s) exist but no MFA-enforcing Conditional Access policy excludes them. A token-service MFA outage will lock the tenant."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML2 - Restrict Admin Privileges'
    }
}
