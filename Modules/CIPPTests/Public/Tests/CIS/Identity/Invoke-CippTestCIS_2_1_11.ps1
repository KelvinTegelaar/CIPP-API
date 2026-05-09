function Invoke-CippTestCIS_2_1_11 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.11) - Comprehensive attachment filtering SHALL be applied
    #>
    param($Tenant)

    try {
        $Malware = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $Malware) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Default = $Malware | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Malware | Select-Object -First 1 }

        # CIS recommends a minimum of 96 file types (the comprehensive list)
        $FileTypeCount = ($Default.FileTypes | Measure-Object).Count

        if ($Default.EnableFileFilter -eq $true -and $FileTypeCount -ge 96) {
            $Status = 'Passed'
            $Result = "Comprehensive attachment filtering is applied — $FileTypeCount file types blocked on '$($Default.Identity)'."
        } else {
            $Status = 'Failed'
            $Result = "Attachment filter on '$($Default.Identity)' is not comprehensive (EnableFileFilter: $($Default.EnableFileFilter), FileTypes count: $FileTypeCount, expected >= 96)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
