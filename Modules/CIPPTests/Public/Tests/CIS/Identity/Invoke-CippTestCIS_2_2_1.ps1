function Invoke-CippTestCIS_2_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.2.1) - Emergency access account activity SHALL be monitored
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_2_1' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Emergency access account activity is monitored' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
}
