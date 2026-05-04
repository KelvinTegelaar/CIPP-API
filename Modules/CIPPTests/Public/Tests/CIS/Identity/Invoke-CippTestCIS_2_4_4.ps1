function Invoke-CippTestCIS_2_4_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.4.4) - Zero-hour auto purge for Microsoft Teams SHALL be on
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_4' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Zero-hour auto purge for Microsoft Teams is on' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
}
