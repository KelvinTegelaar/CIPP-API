function Invoke-CippTestCIS_2_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.1) - Safe Links for Office Applications SHALL be enabled
    #>
    param($Tenant)

    try {
        $SafeLinks = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $SafeLinks) {
            # A Count marker means the cache was collected but the tenant has no Safe Links policy -
            # that is a real failure (Safe Links is not enabled), not a missing cache. No marker
            # means the type was never collected, so a Cache refresh is the correct guidance.
            if (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies' -CountsOnly) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Safe Links policy exists for this tenant, so Safe Links for Office applications is not enabled.' -Risk 'High' -Name 'Safe Links for Office Applications is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicies has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.' -Risk 'High' -Name 'Safe Links for Office Applications is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            }
            return
        }

        $Compliant = $SafeLinks | Where-Object {
            $_.EnableSafeLinksForEmail -eq $true -and
            $_.EnableSafeLinksForTeams -eq $true -and
            $_.EnableSafeLinksForOffice -eq $true -and
            $_.TrackClicks -eq $true -and
            $_.AllowClickThrough -eq $false -and
            $_.ScanUrls -eq $true -and
            $_.EnableForInternalSenders -eq $true -and
            $_.DeliverMessageAfterScan -eq $true -and
            $_.DisableUrlRewrite -eq $false
        }

        if ($Compliant) {
            $Status = 'Passed'
            $Result = "$($Compliant.Count) Safe Links policy/policies meet all CIS requirements:`n`n"
            $Result += ($Compliant | ForEach-Object { "- $($_.Name)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "No Safe Links policy meets every CIS requirement (Email/Teams/Office on, ScanUrls/TrackClicks on, AllowClickThrough off, DisableUrlRewrite off, DeliverMessageAfterScan on, EnableForInternalSenders on)."
            if ($SafeLinks) {
                $Result += "`n`n**Existing policies:**`n"
                $Result += ($SafeLinks | ForEach-Object { "- $($_.Name): SafeLinksForEmail=$($_.EnableSafeLinksForEmail), Office=$($_.EnableSafeLinksForOffice), Teams=$($_.EnableSafeLinksForTeams)" }) -join "`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Links for Office Applications is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Links for Office Applications is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
