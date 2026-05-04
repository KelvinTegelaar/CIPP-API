function Invoke-CippTestCIS_7_2_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.8) - External sharing SHALL be restricted by security group
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_8' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'External sharing is restricted by security group' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
}
