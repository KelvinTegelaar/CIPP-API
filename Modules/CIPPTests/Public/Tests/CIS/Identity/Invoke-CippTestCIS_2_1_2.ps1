function Invoke-CippTestCIS_2_1_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.2) - Common Attachment Types Filter SHALL be enabled
    #>
    param($Tenant)

    try {
        $Malware = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $Malware) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Common Attachment Types Filter is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Default = $Malware | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Malware | Select-Object -First 1 }

        if ($Default.EnableFileFilter -eq $true) {
            $Status = 'Passed'
            $Result = "Common Attachment Types Filter is enabled on '$($Default.Identity)' with $($Default.FileTypes.Count) file types blocked."
        } else {
            $Status = 'Failed'
            $Result = "Common Attachment Types Filter is disabled on '$($Default.Identity)' (EnableFileFilter: $($Default.EnableFileFilter))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Common Attachment Types Filter is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Common Attachment Types Filter is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
