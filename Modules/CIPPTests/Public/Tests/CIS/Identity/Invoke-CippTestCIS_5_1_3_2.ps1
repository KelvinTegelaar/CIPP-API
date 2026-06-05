function Invoke-CippTestCIS_5_1_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.3.2) - 'Restrict user ability to access groups features in My Groups' SHALL be set to 'Yes'
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_2' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Groups > General that, under Self Service Group Management, "Restrict user ability to access groups features in My Groups" is set to Yes.' -Risk 'Informational' -Name "Restrict user ability to access groups features in My Groups is set to 'Yes'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
}
