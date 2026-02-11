function Invoke-CippTestCISAMSEXO142 {
    <#
    .SYNOPSIS
    Tests MS.EXO.14.2 - Spam SHALL be moved to junk email or quarantine

    .DESCRIPTION
    Checks if spam action is set to MoveToJmf or Quarantine in anti-spam policies

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Spam SHALL be moved to junk email or quarantine' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO142' -TenantFilter $Tenant
            return
        }

        $AcceptableActions = @('MoveToJmf', 'Quarantine')
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SpamPolicies) {
            if ($Policy.SpamAction -notin $AcceptableActions) {
                $FailedPolicies.Add([PSCustomObject]@{
                        'Policy Name'    = $Policy.Name
                        'Current Action' = $Policy.SpamAction
                        'Expected'       = 'MoveToJmf or Quarantine'
                    })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies move spam to junk folder or quarantine."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies do not properly handle spam:`n`n"
            $Result += "| Policy Name | Current Action | Expected |`n"
            $Result += "| :---------- | :------------- | :------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.'Policy Name') | $($Policy.'Current Action') | $($Policy.Expected) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO142' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Spam SHALL be moved to junk email or quarantine' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Spam SHALL be moved to junk email or quarantine' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO142' -TenantFilter $Tenant
    }
}
