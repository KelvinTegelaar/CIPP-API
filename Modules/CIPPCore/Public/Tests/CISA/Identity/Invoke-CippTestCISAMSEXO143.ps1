function Invoke-CippTestCISAMSEXO143 {
    <#
    .SYNOPSIS
    Tests MS.EXO.14.3 - Spam filter bypass SHALL be disabled

    .DESCRIPTION
    Checks if anti-spam policies have empty allowed senders and domains lists

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Allowed senders SHOULD NOT be added to anti-spam filter' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO143' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SpamPolicies) {
            $AllowedSenders = if ($Policy.AllowedSenders) { $Policy.AllowedSenders.Count } else { 0 }
            $AllowedSenderDomains = if ($Policy.AllowedSenderDomains) { $Policy.AllowedSenderDomains.Count } else { 0 }

            if ($AllowedSenders -gt 0 -or $AllowedSenderDomains -gt 0) {
                $FailedPolicies.Add([PSCustomObject]@{
                        'Policy Name'     = $Policy.Name
                        'Allowed Senders' = $AllowedSenders
                        'Allowed Domains' = $AllowedSenderDomains
                        'Issue'           = 'Has allowed senders/domains that bypass spam filtering'
                    })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies have no spam filter bypasses configured."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies have spam filter bypasses configured:`n`n"
            $Result += "| Policy Name | Allowed Senders | Allowed Domains | Issue |`n"
            $Result += "| :---------- | :-------------- | :-------------- | :---- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.'Policy Name') | $($Policy.'Allowed Senders') | $($Policy.'Allowed Domains') | $($Policy.Issue) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO143' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Allowed senders SHOULD NOT be added to anti-spam filter' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Allowed senders SHOULD NOT be added to anti-spam filter' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO143' -TenantFilter $Tenant
    }
}
