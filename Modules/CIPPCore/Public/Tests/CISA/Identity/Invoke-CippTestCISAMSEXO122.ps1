function Invoke-CippTestCISAMSEXO122 {
    <#
    .SYNOPSIS
    Tests MS.EXO.12.2 - Safe lists SHOULD NOT be enabled

    .DESCRIPTION
    Checks if anti-spam policies have safe lists disabled

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $SpamPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoHostedContentFilterPolicy'

        if (-not $SpamPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Safe lists SHOULD NOT be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO122' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SpamPolicies | Where-Object { $_.EnableSafeList -eq $true }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies have safe lists disabled."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies have safe lists enabled:`n`n"
            $Result += "| Policy Name | Safe List Enabled |`n"
            $Result += "| :---------- | :---------------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Name) | $($Policy.EnableSafeList) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO122' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Safe lists SHOULD NOT be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Safe lists SHOULD NOT be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO122' -TenantFilter $Tenant
    }
}
