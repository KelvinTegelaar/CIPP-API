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
        $SafeLinksPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSafeLinksPolicy'

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { -not $_.EnableSafeLinksForEmail }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have URL comparison with block-list enabled."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies do not have URL scanning enabled:`n`n"
            $Result += "| Policy Name | Safe Links for Email |`n"
            $Result += "| :---------- | :------------------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Name) | $($Policy.EnableSafeLinksForEmail) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO151' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'URL comparison with block-list SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
    }
}
