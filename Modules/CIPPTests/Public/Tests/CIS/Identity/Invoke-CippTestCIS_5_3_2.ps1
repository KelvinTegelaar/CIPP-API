function Invoke-CippTestCIS_5_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.3.2) - 'Access reviews' for Guest Users SHALL be configured
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_2' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name "'Access reviews' for Guest Users are configured" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
}
