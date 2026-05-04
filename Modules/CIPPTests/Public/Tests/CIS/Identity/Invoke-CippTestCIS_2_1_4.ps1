function Invoke-CippTestCIS_2_1_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.4) - Safe Attachments policy SHALL be enabled
    #>
    param($Tenant)

    try {
        $SA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies'

        if (-not $SA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoSafeAttachmentPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Safe Attachments policy is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
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
