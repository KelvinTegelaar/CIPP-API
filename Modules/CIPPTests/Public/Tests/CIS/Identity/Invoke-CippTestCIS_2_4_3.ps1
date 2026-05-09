function Invoke-CippTestCIS_2_4_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.4.3) - Microsoft Defender for Cloud Apps SHALL be enabled and configured
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_3' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Microsoft Defender for Cloud Apps is enabled and configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Cloud Apps'
}
