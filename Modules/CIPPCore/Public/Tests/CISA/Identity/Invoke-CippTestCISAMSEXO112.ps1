function Invoke-CippTestCISAMSEXO112 {
    <#
    .SYNOPSIS
    Tests MS.EXO.11.2 - User warnings, comparable to the user safety tips included with EOP, SHOULD be displayed

    .DESCRIPTION
    Checks if impersonation safety tips are enabled in preset security policies

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $PresetPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoPresetSecurityPolicy'

        if (-not $PresetPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'User warnings comparable to EOP safety tips SHOULD be displayed' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection' -TestId 'CISAMSEXO112' -TenantFilter $Tenant
            return
        }

        $PoliciesWithTips = $PresetPolicies | Where-Object {
            ($_.EnableSimilarUsersSafetyTips -eq $true) -or
            ($_.EnableSimilarDomainsSafetyTips -eq $true) -or
            ($_.EnableUnusualCharactersSafetyTips -eq $true)
        }

        if ($PoliciesWithTips.Count -gt 0) {
            $Result = "✅ **Pass**: $($PoliciesWithTips.Count) policy/policies have impersonation safety tips enabled:`n`n"
            $Result += "| Policy | Similar Users Tips | Similar Domains Tips | Unusual Characters Tips |`n"
            $Result += "| :----- | :----------------- | :------------------- | :---------------------- |`n"
            foreach ($Policy in $PoliciesWithTips) {
                $Result += "| $($Policy.Identity) | $($Policy.EnableSimilarUsersSafetyTips) | $($Policy.EnableSimilarDomainsSafetyTips) | $($Policy.EnableUnusualCharactersSafetyTips) |`n"
            }
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: No policies found with impersonation safety tips enabled.`n`n"
            $Result += "Enable safety tips in preset security policies to warn users about potential impersonation."
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO112' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'User warnings comparable to EOP safety tips SHOULD be displayed' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'User warnings comparable to EOP safety tips SHOULD be displayed' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection' -TestId 'CISAMSEXO112' -TenantFilter $Tenant
    }
}
