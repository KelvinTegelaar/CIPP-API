function Invoke-CippTestCIS_5_2_4_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.4.4) - Users SHALL be notified on password resets
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_4_4' -TestType 'Identity' -Status 'Informational' -ResultMarkdown "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Notifications that 'Notify users on password resets' is set to Yes." -Risk 'Informational' -Name 'Users are notified on password resets' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
}
