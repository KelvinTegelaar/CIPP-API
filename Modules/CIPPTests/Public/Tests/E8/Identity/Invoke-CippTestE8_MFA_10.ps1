function Invoke-CippTestE8_MFA_10 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML3) - Phishing-resistant authentication strength is required for all users
    #>
    param($Tenant)

    $TestId = 'E8_MFA_10'
    $Name = 'Phishing-resistant authentication strength is required for all users'
    $PhishResistantId = '00000000-0000-0000-0000-000000000004'

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
            return
        }

        $Match = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            ($_.conditions.users.includeUsers -contains 'All') -and
            ($_.conditions.applications.includeApplications -contains 'All') -and
            $_.grantControls.authenticationStrength -and
            $_.grantControls.authenticationStrength.id -eq $PhishResistantId
        }

        if ($Match) {
            $Status = 'Passed'
            $Result = "$($Match.Count) Conditional Access policy/policies enforce phishing-resistant MFA tenant-wide:`n`n" +
                (($Match | ForEach-Object { "- $($_.displayName)" }) -join "`n")
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy enforces the *Phishing-resistant MFA* authentication strength on All Users + All Cloud Apps.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
    }
}
