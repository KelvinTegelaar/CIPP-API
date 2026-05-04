function Invoke-CippTestCIS_5_3_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.3.5) - Approval SHALL be required for Privileged Role Administrator activation
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_5' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Approval is required for Privileged Role Administrator activation' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
}
