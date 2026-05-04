function Invoke-CippTestCIS_5_2_2_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.4) - Sign-in frequency SHALL be enabled and browser sessions not persistent for administrative users
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $CA -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ConditionalAccessPolicies or Roles) not found.' -Risk 'Medium' -Name 'Sign-in frequency for administrative users is configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Session Management'
            return
        }

        $PrivRoleIds = ($Roles | Where-Object { $_.isPrivileged -eq $true }).id

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeRoles -and
            (@($_.conditions.users.includeRoles) | Where-Object { $_ -in $PrivRoleIds }).Count -gt 0 -and
            $_.sessionControls -and
            $_.sessionControls.signInFrequency -and
            $_.sessionControls.signInFrequency.isEnabled -eq $true -and
            $_.sessionControls.persistentBrowser -and
            $_.sessionControls.persistentBrowser.mode -eq 'never'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies enforce admin sign-in frequency + non-persistent browser:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled CA policy enforces sign-in frequency AND non-persistent browser for privileged roles.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Sign-in frequency for administrative users is configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Session Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Sign-in frequency for administrative users is configured' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Session Management'
    }
}
