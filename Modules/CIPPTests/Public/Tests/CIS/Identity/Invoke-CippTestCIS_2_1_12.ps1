function Invoke-CippTestCIS_2_1_12 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.12) - Connection filter IP allow list SHALL NOT be used
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_12' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Connection filter IP allow list is not used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
}
