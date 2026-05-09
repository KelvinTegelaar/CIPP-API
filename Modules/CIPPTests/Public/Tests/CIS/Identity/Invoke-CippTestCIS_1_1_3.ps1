function Invoke-CippTestCIS_1_1_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.1.3) - Between two and four global admins SHALL be designated
    #>
    param($Tenant)

    try {
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'
        $RoleAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignments'

        if (-not $Roles -or -not $RoleAssignments) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Roles or RoleAssignments) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $GA = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1
        if (-not $GA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Global Administrator role not found in tenant role definitions.' -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $GACount = (($RoleAssignments | Where-Object { $_.roleDefinitionId -eq $GA.id }).principalId | Select-Object -Unique).Count

        if ($GACount -ge 2 -and $GACount -le 4) {
            $Status = 'Passed'
            $Result = "Tenant has $GACount Global Administrator(s) — within the recommended 2–4 range."
        } elseif ($GACount -lt 2) {
            $Status = 'Failed'
            $Result = "Tenant has only $GACount Global Administrator(s). At least 2 are required for redundancy."
        } else {
            $Status = 'Failed'
            $Result = "Tenant has $GACount Global Administrator(s). Maximum recommended is 4 — reduce role spread to lower the attack surface."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Between two and four global admins are designated' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Privileged Access'
    }
}
