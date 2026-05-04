function Invoke-CippTestCIS_5_2_2_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.5) - 'Phishing-resistant MFA strength' SHALL be required for Administrators
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $Strengths = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationStrengths'

        if (-not $CA -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (ConditionalAccessPolicies or Roles) not found.' -Risk 'High' -Name "'Phishing-resistant MFA strength' is required for Administrators" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
            return
        }

        $PrivRoleIds = ($Roles | Where-Object { $_.isPrivileged -eq $true }).id
        $PhishResistantId = '00000000-0000-0000-0000-000000000004'  # Built-in 'Phishing-resistant MFA' strength

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeRoles -and
            (@($_.conditions.users.includeRoles) | Where-Object { $_ -in $PrivRoleIds }).Count -gt 0 -and
            $_.grantControls.authenticationStrength -and
            $_.grantControls.authenticationStrength.id -eq $PhishResistantId
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies require phishing-resistant MFA for privileged roles:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy enforces phishing-resistant MFA strength for privileged roles.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "'Phishing-resistant MFA strength' is required for Administrators" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "'Phishing-resistant MFA strength' is required for Administrators" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
    }
}
