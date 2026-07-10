function Invoke-CippTestE8_MFA_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML1) - A Conditional Access policy enforces MFA for all users
    #>
    param($Tenant)

    $TestId = 'E8_MFA_02'
    $Name = 'A Conditional Access policy enforces MFA for all users on all cloud apps'

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
            return
        }

        $Match = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            ($_.conditions.users.includeUsers -contains 'All') -and
            ($_.conditions.applications.includeApplications -contains 'All') -and
            (
                ($_.grantControls.builtInControls -contains 'mfa') -or
                $_.grantControls.authenticationStrength
            )
        }

        if ($Match) {
            $Status = 'Passed'
            $Result = "$($Match.Count) Conditional Access policy/policies enforce MFA on all users for all cloud apps:`n`n" +
                (($Match | ForEach-Object { "- $($_.displayName)" }) -join "`n")
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets All Users + All Cloud Apps with an MFA grant control.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    }
}
