function Invoke-CippTestCIS_6_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.3.1) - Users installing Outlook add-ins SHALL NOT be allowed
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_3_1' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Users installing Outlook add-ins is not allowed' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
}
