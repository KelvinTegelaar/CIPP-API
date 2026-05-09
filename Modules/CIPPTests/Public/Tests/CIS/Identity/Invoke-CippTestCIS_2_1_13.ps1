function Invoke-CippTestCIS_2_1_13 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.13) - Connection filter safe list SHALL be off
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_13' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Connection filter safe list is off' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
}
