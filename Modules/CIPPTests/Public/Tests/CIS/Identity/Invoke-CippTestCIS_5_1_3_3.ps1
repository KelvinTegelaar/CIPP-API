function Invoke-CippTestCIS_5_1_3_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.3.3) - 'Owners can manage group membership requests in My Groups' SHALL be set to 'No'
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_3' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Groups > General that "Owners can manage group membership requests in My Groups" is set to No.' -Risk 'Informational' -Name "Owners can manage group membership requests in My Groups is set to 'No'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
}
