function Invoke-CippTestCIS_2_4_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.4.5) - 'AIR' remediation SHALL be enabled
    #>
    param($Tenant)

    Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_5' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'This is a manual control. Verify in the Microsoft Defender portal > Settings > Endpoints (or Email & collaboration policies) that Automated Investigation and Response (AIR) remediation is enabled.' -Risk 'Informational' -Name 'AIR remediation is enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
}
