function Invoke-CippTestCIS_2_1_14 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.14) - Inbound anti-spam policies SHALL NOT contain allowed domains
    #>
    param($Tenant)

    try {
        $Inbound = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $Inbound) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_14' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Inbound anti-spam policies do not contain allowed domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Offending = $Inbound | Where-Object { $_.AllowedSenderDomains -and $_.AllowedSenderDomains.Count -gt 0 }

        if (-not $Offending) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All $($Inbound.Count) inbound anti-spam policy/policies have no allowed sender domains.")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($Offending.Count) inbound anti-spam policy/policies have allowed sender domains configured:`n`n")
            foreach ($P in $Offending) {
                $null = $Result.Append("- **$($P.Identity)**: $($P.AllowedSenderDomains -join ', ')`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_14' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Inbound anti-spam policies do not contain allowed domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_14' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Inbound anti-spam policies do not contain allowed domains' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
