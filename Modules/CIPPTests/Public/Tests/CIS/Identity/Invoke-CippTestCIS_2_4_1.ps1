function Invoke-CippTestCIS_2_4_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.4.1) - Priority account protection SHALL be enabled and configured
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_1' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Priority account protection is enabled and configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
}
