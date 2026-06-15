function Invoke-CippTestCIS_5_2_4_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.4.5) - All admins SHALL be notified when other admins reset their password
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_4_5' -TestType 'Identity' -Status 'Informational' -ResultMarkdown "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Notifications that 'Notify all admins when other admins reset their password' is set to Yes." -Risk 'Informational' -Name 'All admins are notified when other admins reset their password' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
}
