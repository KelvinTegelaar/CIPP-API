function Invoke-CippTestCIS_2_1_11 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.11) - Comprehensive attachment filtering SHALL be applied
    #>
    param($Tenant)

    try {
        $Malware = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $Malware) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        # Comprehensive filtering is enforced by whichever malware policy applies via its rule, not
        # only the built-in Default (which is capped at ~50 file types) - CIPP's own standard creates
        # a non-default policy for exactly this. Grade the best policy that meets the bar.
        # CIS v7 defines a comprehensive list of 186 extensions and requires at least 90% adoption (>= 168).
        $Policies = @($Malware)
        $Compliant = $Policies | Where-Object { $_.EnableFileFilter -eq $true -and (($_.FileTypes | Measure-Object).Count -ge 168) } | Select-Object -First 1

        if ($Compliant) {
            $FileTypeCount = ($Compliant.FileTypes | Measure-Object).Count
            $Status = 'Passed'
            $Result = "Comprehensive attachment filtering is applied — $FileTypeCount file types blocked on '$($Compliant.Identity)'."
        } else {
            $Default = $Policies | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
            if (-not $Default) { $Default = $Policies | Select-Object -First 1 }
            $FileTypeCount = ($Default.FileTypes | Measure-Object).Count
            $Status = 'Failed'
            $Result = "Attachment filter on '$($Default.Identity)' is not comprehensive (EnableFileFilter: $($Default.EnableFileFilter), FileTypes count: $FileTypeCount, expected >= 168 — 90% of the CIS v7 186-extension list)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_11' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Comprehensive attachment filtering is applied' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
