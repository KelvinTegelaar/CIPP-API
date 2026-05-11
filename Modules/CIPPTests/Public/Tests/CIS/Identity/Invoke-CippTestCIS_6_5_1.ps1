function Invoke-CippTestCIS_6_5_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.5.1) - Modern authentication for Exchange Online SHALL be enabled
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found.' -Risk 'High' -Name 'Modern authentication for Exchange Online is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $Org | Select-Object -First 1

        if ($Cfg.OAuth2ClientProfileEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Modern authentication is enabled for Exchange Online (OAuth2ClientProfileEnabled: true).'
        } else {
            $Status = 'Failed'
            $Result = "Modern authentication is disabled (OAuth2ClientProfileEnabled: $($Cfg.OAuth2ClientProfileEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Modern authentication for Exchange Online is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Modern authentication for Exchange Online is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
