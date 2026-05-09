function Invoke-CippTestCIS_7_2_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.7) - Link sharing SHALL be restricted in SharePoint and OneDrive
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        $Acceptable = @('Direct', 'Internal')

        if ($Cfg.DefaultSharingLinkType -in $Acceptable) {
            $Status = 'Passed'
            $Result = "DefaultSharingLinkType is restricted ($($Cfg.DefaultSharingLinkType))."
        } else {
            $Status = 'Failed'
            $Result = "DefaultSharingLinkType is too permissive ($($Cfg.DefaultSharingLinkType)). Set to Direct or Internal."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Link sharing is restricted in SharePoint and OneDrive' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
