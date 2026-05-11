function Invoke-CippTestCIS_7_2_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.6) - SharePoint external sharing SHALL be restricted
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'SharePoint external sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        $Mode = $Cfg.SharingDomainRestrictionMode
        $AllowList = $Cfg.SharingAllowedDomainList
        $BlockList = $Cfg.SharingBlockedDomainList

        $Pass = ($Mode -eq 'AllowList' -and -not [string]::IsNullOrWhiteSpace($AllowList)) -or
                ($Mode -eq 'BlockList' -and -not [string]::IsNullOrWhiteSpace($BlockList))

        if ($Pass) {
            $Status = 'Passed'
            $Result = "External sharing is restricted by domain list (mode: $Mode)."
        } else {
            $Status = 'Failed'
            $Result = "External sharing is not restricted by domain list (SharingDomainRestrictionMode: $Mode)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SharePoint external sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SharePoint external sharing is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    }
}
