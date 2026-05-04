function Invoke-CippTestCIS_5_1_2_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.5) - The option to remain signed in SHALL be hidden
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_5' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'The option to remain signed in is hidden' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
}
