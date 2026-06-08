function Invoke-CippTestCISAMSEXO151 {
    <#
    .SYNOPSIS
    Tests MS.EXO.15.1 - URL comparison with a block-list SHOULD be enabled

    .DESCRIPTION
    Checks if Safe Links policies have URL scanning enabled

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $SafeLinksPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { -not $_.EnableSafeLinksForEmail }

        if ($FailedPolicies.Count -eq 0) {
            $Result = [System.Text.StringBuilder]::new("✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have URL comparison with block-list enabled.")
            $Status = 'Passed'
        } else {
            $Result = [System.Text.StringBuilder]::new("❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies do not have URL scanning enabled:`n`n")
            $null = $Result.Append("| Policy Name | Safe Links for Email |`n")
            $null = $Result.Append("| :---------- | :------------------- |`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Name) | $($Policy.EnableSafeLinksForEmail) |`n")
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO151' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
    }
}
