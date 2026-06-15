function Invoke-CippTestCIS_5_2_4_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.4.3) - SSPR registration and authentication re-confirmation SHALL be required
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_4_3' -TestType 'Identity' -Status 'Informational' -ResultMarkdown "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Registration that 'Require users to register when signing in' is Yes and re-confirmation of authentication information is required on a defined cadence." -Risk 'Informational' -Name 'SSPR registration and authentication re-confirmation are required' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
}
