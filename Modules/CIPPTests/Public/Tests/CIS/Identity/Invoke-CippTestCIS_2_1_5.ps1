function Invoke-CippTestCIS_2_1_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.5) - Safe Attachments for SharePoint, OneDrive, and Microsoft Teams SHALL be enabled
    #>
    param($Tenant)

    try {
        $Atp = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $Atp) {
            # A Count marker means the cache was collected but the tenant has no ATP policy - that is
            # a real failure, not a missing cache. No marker means the type was never collected, so a
            # Cache refresh is the correct guidance.
            if (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365' -CountsOnly) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No ATP policy for Office 365 exists for this tenant, so Safe Attachments for SharePoint, OneDrive and Teams is not enabled.' -Risk 'High' -Name 'Safe Attachments for SharePoint, OneDrive, and Teams is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoAtpPolicyForO365 has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.' -Risk 'High' -Name 'Safe Attachments for SharePoint, OneDrive, and Teams is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            }
            return
        }

        $Cfg = $Atp | Select-Object -First 1

        $Required = @{
            EnableATPForSPOTeamsODB    = $true
            EnableSafeDocs             = $true
            AllowSafeDocsOpen          = $false
        }
        $Failures = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $Required.Keys) {
            if ($Cfg.$key -ne $Required[$key]) {
                $Failures.Add("$key = $($Cfg.$key) (expected $($Required[$key]))")
            }
        }

        if ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'Safe Attachments for SharePoint, OneDrive and Teams is fully enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Configuration mismatch on ATP policy:`n`n" + (($Failures | ForEach-Object { "- $_" }) -join "`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Attachments for SharePoint, OneDrive, and Teams is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Attachments for SharePoint, OneDrive, and Teams is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
