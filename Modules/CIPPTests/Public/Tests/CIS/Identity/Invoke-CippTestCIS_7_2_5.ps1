function Invoke-CippTestCIS_7_2_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.5) - SharePoint guest users SHALL NOT share items they don't own
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "SharePoint guest users cannot share items they don't own" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        if ($Cfg.PreventExternalUsersFromResharing -eq $true) {
            $Status = 'Passed'
            $Result = 'External users cannot reshare (PreventExternalUsersFromResharing: true).'
        } else {
            $Status = 'Failed'
            $Result = "External users can reshare (PreventExternalUsersFromResharing: $($Cfg.PreventExternalUsersFromResharing))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "SharePoint guest users cannot share items they don't own" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "SharePoint guest users cannot share items they don't own" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
