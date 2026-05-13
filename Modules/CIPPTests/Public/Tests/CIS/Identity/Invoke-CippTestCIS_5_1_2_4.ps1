function Invoke-CippTestCIS_5_1_2_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.4) - Access to the Entra admin center SHALL be restricted
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_4' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Access to the Entra admin center is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
}
