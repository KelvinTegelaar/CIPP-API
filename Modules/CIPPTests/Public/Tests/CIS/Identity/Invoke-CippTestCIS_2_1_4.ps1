function Invoke-CippTestCIS_2_1_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.4) - Safe Attachments policy SHALL be enabled
    #>
    param($Tenant)

    try {
        $SA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies'

        if (-not $SA) {
            # A Count marker means the cache was collected but the tenant has no Safe Attachments
            # policy - that is a real failure, not a missing cache. No marker means the type was
            # never collected, so a Cache refresh is the correct guidance.
            if (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies' -CountsOnly) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'No Safe Attachments policy exists for this tenant, so Safe Attachments is not enabled.' -Risk 'High' -Name 'Safe Attachments policy is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoSafeAttachmentPolicies has not been collected for this tenant. Run a Cache refresh (Cache & Tests); if it persists, the tenant may not have Defender for Office 365.' -Risk 'High' -Name 'Safe Attachments policy is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            }
            return
        }

        $Compliant = $SA | Where-Object { $_.Enable -eq $true -and $_.Action -in @('Block', 'Replace', 'DynamicDelivery') }

        if ($Compliant) {
            $Status = 'Passed'
            $Result = "$($Compliant.Count) Safe Attachments policy/policies are enabled with a blocking action:`n`n"
            $Result += ($Compliant | ForEach-Object { "- $($_.Name) (Action: $($_.Action))" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Safe Attachments policy with a blocking action (Block/Replace/DynamicDelivery) was found.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Attachments policy is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Attachments policy is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
