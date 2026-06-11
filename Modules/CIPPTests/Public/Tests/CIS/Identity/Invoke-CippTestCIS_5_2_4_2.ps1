function Invoke-CippTestCIS_5_2_4_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.4.2) - Two methods SHALL be required for password reset
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_4_2' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Authentication methods that the Number of methods required to reset is set to 2.' -Risk 'Informational' -Name 'Two methods are required for password reset' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
}
