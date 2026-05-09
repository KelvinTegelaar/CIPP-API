function Invoke-CippTestCIS_5_2_4_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.4.1) - 'Self service password reset enabled' SHALL be set to 'All'
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_4_1' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name "'Self service password reset enabled' is set to 'All'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
}
