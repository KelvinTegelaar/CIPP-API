function Invoke-CippTestCIS_2_1_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.5) - Safe Attachments for SharePoint, OneDrive, and Microsoft Teams SHALL be enabled
    #>
    param($Tenant)

    try {
        $Atp = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $Atp) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoAtpPolicyForO365 cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Safe Attachments for SharePoint, OneDrive, and Teams is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Cfg = $Atp | Select-Object -First 1

        $Required = @{
            EnableATPForSPOTeamsODB    = $true
            EnableSafeDocs             = $true
            AllowSafeDocsOpen          = $false
        }
        $Failures = @()
        foreach ($key in $Required.Keys) {
            if ($Cfg.$key -ne $Required[$key]) {
                $Failures += "$key = $($Cfg.$key) (expected $($Required[$key]))"
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
