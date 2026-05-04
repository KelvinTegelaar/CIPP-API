function Invoke-CippTestCIS_3_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (3.3.1) - Information Protection sensitivity label policies SHALL be published
    #>
    param($Tenant)

    try {
        $Labels = Get-CIPPTestData -TenantFilter $Tenant -Type 'SensitivityLabels'

        if (-not $Labels) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SensitivityLabels cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
            return
        }

        $Published = $Labels | Where-Object { $_.IsValid -eq $true -or $_.PolicyName }

        if ($Published.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($Published.Count) sensitivity label(s) appear to be published in the tenant."
        } else {
            $Status = 'Failed'
            $Result = "No published sensitivity labels were found. Create and publish a label set covering at least Public / Internal / Confidential."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Information Protection sensitivity label policies are published' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Information Protection'
    }
}
