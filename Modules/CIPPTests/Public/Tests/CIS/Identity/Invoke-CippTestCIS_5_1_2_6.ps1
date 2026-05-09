function Invoke-CippTestCIS_5_1_2_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.6) - 'LinkedIn account connections' SHALL be disabled
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_6' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name "'LinkedIn account connections' is disabled" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
}
