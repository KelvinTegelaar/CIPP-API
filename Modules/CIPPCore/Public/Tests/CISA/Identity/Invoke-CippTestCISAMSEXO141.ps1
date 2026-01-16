function Invoke-CippTestCISAMSEXO141 {
    <#
    .SYNOPSIS
    Tests MS.EXO.14.1 - High confidence spam SHALL be quarantined

    .DESCRIPTION
    Checks if high confidence spam action is set to Quarantine in anti-spam policies

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'High confidence spam SHALL be quarantined' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO141' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SpamPolicies | Where-Object { $_.HighConfidenceSpamAction -ne 'Quarantine' }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies quarantine high confidence spam."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies do not quarantine high confidence spam:`n`n"
            $Result += "| Policy Name | Current Action | Expected |`n"
            $Result += "| :---------- | :------------- | :------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.'Policy Name') | $($Policy.'Current Action') | $($Policy.Expected) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO141' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'High confidence spam SHALL be quarantined' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'High confidence spam SHALL be quarantined' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO141' -TenantFilter $Tenant
    }
}
