function Invoke-CippTestCIS_1_3_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.8) - Sways SHALL NOT be shared with people outside of the organization
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_8' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a task performed manually.' -Risk 'Informational' -Name 'Sways cannot be shared with people outside of your organization' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
}
