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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO142' -TenantFilter $Tenant
            return
        }

        $AcceptableActions = @('MoveToJmf', 'Quarantine')
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SpamPolicies) {
            if ($Policy.SpamAction -notin $AcceptableActions) {
                $FailedPolicies.Add([PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Current Action' = $Policy.SpamAction
                    'Expected' = 'MoveToJmf or Quarantine'
                })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies move spam to junk folder or quarantine."
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies do not properly handle spam:`n`n"
            $Result += ($FailedPolicies | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO142' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO142' -TenantFilter $Tenant
    }
}
