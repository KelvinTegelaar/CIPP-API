function Invoke-CippTestCIS_3_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (3.3.1) - Information Protection sensitivity label policies SHALL be published
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoLabelPolicies'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No sensitivity label policies found, the tenant has no Purview/AIP license, or the ExoLabels cache has not been collected. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
            return
        }

        $Published = @(foreach ($Policy in $Policies) { if ($Policy.Type -eq 'PublishedSensitivityLabel' -and $Policy.Enabled -ne $false -and @($Policy.Labels).Count -gt 0) { $Policy } })

        if ($Published.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($Published.Count) sensitivity label policy(s) publish labels in the tenant: $($Published.Name -join ', ')."
        } else {
            $Status = 'Failed'
            $Result = "No enabled sensitivity label policy publishes any labels. Create and publish a label set covering at least Public / Internal / Confidential."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
    }
}
