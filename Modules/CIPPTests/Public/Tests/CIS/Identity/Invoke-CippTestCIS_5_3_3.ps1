function Invoke-CippTestCIS_5_3_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.3.3) - 'Access reviews' for privileged roles SHALL be configured
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_3' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name "'Access reviews' for privileged roles are configured" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
}
