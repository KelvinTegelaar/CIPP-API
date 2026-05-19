function Invoke-CippTestCIS_1_1_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.1.2) - At least two emergency access (break-glass) accounts SHALL be defined

    .DESCRIPTION
    Identifies likely break-glass accounts by looking for cloud-only Global Administrator
    accounts whose UPN contains common break-glass keywords. Manual verification is required.
    #>
    param($Tenant)

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Roles -or -not $RoleAssignments -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles, RoleAssignments, or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Two emergency access accounts have been defined' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $GA = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1
        if (-not $GA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Global Administrator role not found in tenant role definitions.' -Risk 'High' -Name 'Two emergency access accounts have been defined' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $GAUserIds = ($RoleAssignments | Where-Object { $_.roleDefinitionId -eq $GA.id }).principalId
        $GAUsers = $Users | Where-Object { $_.id -in $GAUserIds }
        $BreakGlassPattern = 'breakglass|break-glass|emergency|cipp-bg|bg-admin'
        $LikelyBG = $GAUsers | Where-Object { $_.userPrincipalName -match $BreakGlassPattern -and $_.onPremisesSyncEnabled -ne $true }

        if ($LikelyBG.Count -ge 2) {
            $Status = 'Passed'
            $Result = "Found $($LikelyBG.Count) likely emergency access accounts. Verify they meet break-glass requirements (excluded from CA, monitored, MFA-registered).`n`n"
            $Result += ($LikelyBG | ForEach-Object { "- $($_.userPrincipalName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "Found $($LikelyBG.Count) cloud-only Global Administrator(s) matching break-glass naming. Required: at least 2.`n`nNote: This test only flags GA accounts whose UPN matches common break-glass keywords. If your break-glass accounts use a different naming convention this test will report a false negative."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Two emergency access accounts have been defined' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Two emergency access accounts have been defined' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
