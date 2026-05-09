function Invoke-CippTestCIS_7_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.3.1) - Office 365 SharePoint infected files SHALL be disallowed for download
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Office 365 SharePoint infected files are disallowed for download' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        if ($Cfg.DisallowInfectedFileDownload -eq $true) {
            $Status = 'Passed'
            $Result = 'Infected files cannot be downloaded (DisallowInfectedFileDownload: true).'
        } else {
            $Status = 'Failed'
            $Result = "Infected files are still downloadable (DisallowInfectedFileDownload: $($Cfg.DisallowInfectedFileDownload))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Office 365 SharePoint infected files are disallowed for download' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Office 365 SharePoint infected files are disallowed for download' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
