function Invoke-CippTestCIS_6_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (6.2.3) - Email from external senders SHALL be identified
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoExternalInOutlook'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoExternalInOutlook cache not found.' -Risk 'Medium' -Name 'Email from external senders is identified' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Cfg = $Org | Select-Object -First 1
        $External = $Cfg.Enabled

        if ($External -eq $true) {
            $Status = 'Passed'
            $Result = 'External sender callouts are enabled in Outlook (Enabled: true).'
        } else {
            $Status = 'Failed'
            $Result = "External sender callouts are disabled (Enabled: $External). Run Set-ExternalInOutlook -Enabled $true."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Email from external senders is identified' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Email from external senders is identified' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
