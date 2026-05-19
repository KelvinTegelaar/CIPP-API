function Invoke-CippTestCIS_6_5_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.5.4) - SMTP AUTH SHALL be disabled
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found.' -Risk 'High' -Name 'SMTP AUTH is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $Org | Select-Object -First 1

        if ($Cfg.SmtpClientAuthenticationDisabled -eq $true) {
            $Status = 'Passed'
            $Result = 'SMTP AUTH is disabled organisation-wide (SmtpClientAuthenticationDisabled: true).'
        } else {
            $Status = 'Failed'
            $Result = "SMTP AUTH is enabled organisation-wide (SmtpClientAuthenticationDisabled: $($Cfg.SmtpClientAuthenticationDisabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SMTP AUTH is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMTP AUTH is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
