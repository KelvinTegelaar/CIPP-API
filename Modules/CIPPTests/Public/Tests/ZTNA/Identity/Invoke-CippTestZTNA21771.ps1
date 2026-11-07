function Invoke-CippTestZTNA21771 {
    <#
    .SYNOPSIS
    Inactive applications don't have highly privileged built-in roles
    #>
    param($Tenant)

    $TestId = 'ZTNA21771'
    $Name = "Inactive applications don't have highly privileged built-in roles"

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID P1, which the service principal sign-in activity report requires. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        $ServicePrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'
        $SignInActivities = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipalSignInActivities'
        $RoleDefinitions = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleDefinitions'
        if (-not $ServicePrincipals -or -not $SignInActivities -or -not $RoleDefinitions) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Service principals, service principal sign-in activity or role definitions not found in database. Data collection may not have completed yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        # Active PIM instances when PIM data exists, otherwise all role assignments, as upstream does for P2 and P1 tenants.
        $ActiveAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        if (-not $ActiveAssignments) { $ActiveAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments' }
        $EligibleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'

        $SpById = @{}
        foreach ($Sp in $ServicePrincipals) { $SpById[[string]$Sp.id] = $Sp }
        $PrivilegedRoleNames = @{}
        foreach ($Definition in $RoleDefinitions) {
            if ($Definition.isPrivileged -eq $true) { $PrivilegedRoleNames[[string]$Definition.id] = $Definition.displayName }
        }

        $Assignments = @(
            foreach ($Assignment in $ActiveAssignments) { if ($PrivilegedRoleNames.ContainsKey([string]$Assignment.roleDefinitionId)) { @{ Row = $Assignment; Type = 'Permanent' } } }
            foreach ($Assignment in $EligibleAssignments) { if ($PrivilegedRoleNames.ContainsKey([string]$Assignment.roleDefinitionId)) { @{ Row = $Assignment; Type = 'Eligible' } } }
        )
        $GroupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Assignment in $Assignments) {
            if (-not $SpById.ContainsKey([string]$Assignment.Row.principalId)) { [void]$GroupIds.Add([string]$Assignment.Row.principalId) }
        }
        $GroupMembers = @{}
        if ($GroupIds.Count -gt 0) {
            Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups' -Fields 'id', 'members' -Stream | ForEach-Object {
                if ($GroupIds.Contains([string]$_.id)) { $GroupMembers[[string]$_.id] = @($_.members.id) }
            }
        }

        $Apps = [ordered]@{}
        foreach ($Assignment in $Assignments) {
            $PrincipalId = [string]$Assignment.Row.principalId
            $HolderIds = if ($SpById.ContainsKey($PrincipalId)) { @($PrincipalId) } else { @($GroupMembers[$PrincipalId]).Where({ $SpById.ContainsKey([string]$_) }) }
            foreach ($HolderId in $HolderIds) {
                $Key = "$HolderId|$($Assignment.Type)"
                if (-not $Apps.Contains($Key)) {
                    $Apps[$Key] = [PSCustomObject]@{ Id = [string]$HolderId; Type = $Assignment.Type; Roles = [System.Collections.Generic.SortedSet[string]]::new() }
                }
                [void]$Apps[$Key].Roles.Add([string]$PrivilegedRoleNames[[string]$Assignment.Row.roleDefinitionId])
            }
        }

        $LastSignInByAppId = @{}
        foreach ($Activity in $SignInActivities) { $LastSignInByAppId[[string]$Activity.appId] = $Activity.lastSignInActivity.lastSignInDateTime }
        $Inactive = [System.Collections.Generic.List[object]]::new()
        $Active = [System.Collections.Generic.List[object]]::new()
        foreach ($App in $Apps.Values) {
            $Sp = $SpById[$App.Id]
            $Row = [PSCustomObject]@{
                Id          = $App.Id
                AppId       = $Sp.appId
                DisplayName = $Sp.displayName
                Publisher   = $Sp.publisherName
                Roles       = @($App.Roles) -join ', '
                Type        = $App.Type
                LastSignIn  = $LastSignInByAppId[[string]$Sp.appId]
            }
            if ($Row.LastSignIn) { $Active.Add($Row) } else { $Inactive.Add($Row) }
        }

        $Status = if ($Inactive.Count -eq 0) { 'Passed' } else { 'Failed' }
        $Result = [System.Text.StringBuilder]::new()
        if ($Status -eq 'Passed') {
            [void]$Result.Append("No inactive applications with privileged Entra built-in roles`n")
        } else {
            [void]$Result.Append("Found $($Inactive.Count) inactive application(s) with privileged Entra built-in roles`n")
        }
        if ($Apps.Count -gt 0) {
            [void]$Result.Append("`n## Apps with privileged Entra built-in roles`n`n")
            [void]$Result.Append("| | Name | Role | Assignment | Publisher | Last sign in |`n")
            [void]$Result.Append("| :--- | :--- | :--- | :--- | :--- | :--- |`n")
            $Shown = 0
            foreach ($Group in @(@{ Icon = '❌'; Rows = $Inactive }, @{ Icon = '✅'; Rows = $Active })) {
                foreach ($Row in $Group.Rows) {
                    if ($Shown -ge 50) { break }
                    $Shown++
                    $Link = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($Row.Id)/appId/$($Row.AppId)"
                    $LastSignIn = if ($Row.LastSignIn) { $Row.LastSignIn } else { 'Never' }
                    [void]$Result.Append("| $($Group.Icon) | [$($Row.DisplayName)]($Link) | $($Row.Roles) | $($Row.Type) | $($Row.Publisher) | $LastSignIn |`n")
                }
            }
            if ($Apps.Count -gt $Shown) {
                [void]$Result.Append("`n... and $($Apps.Count - $Shown) more application(s)`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
    }
}
