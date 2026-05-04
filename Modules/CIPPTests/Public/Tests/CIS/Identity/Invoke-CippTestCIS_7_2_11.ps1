function Invoke-CippTestCIS_7_2_11 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.11) - SharePoint default sharing link permission SHALL be set
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_11' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'The SharePoint default sharing link permission is set' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        if ($Cfg.DefaultLinkPermission -eq 'View') {
            $Status = 'Passed'
            $Result = 'DefaultLinkPermission is set to View.'
        } else {
            $Status = 'Failed'
            $Result = "DefaultLinkPermission is set to $($Cfg.DefaultLinkPermission). CIS requires View."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'The SharePoint default sharing link permission is set' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_11' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'The SharePoint default sharing link permission is set' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
