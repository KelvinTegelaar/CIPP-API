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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoHostedContentFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO143' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SpamPolicies) {
            $AllowedSenders = if ($Policy.AllowedSenders) { $Policy.AllowedSenders.Count } else { 0 }
            $AllowedSenderDomains = if ($Policy.AllowedSenderDomains) { $Policy.AllowedSenderDomains.Count } else { 0 }

            if ($AllowedSenders -gt 0 -or $AllowedSenderDomains -gt 0) {
                $FailedPolicies.Add([PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Allowed Senders' = $AllowedSenders
                    'Allowed Domains' = $AllowedSenderDomains
                    'Issue' = 'Has allowed senders/domains that bypass spam filtering'
                })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SpamPolicies.Count) anti-spam policy/policies have no spam filter bypasses configured."
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SpamPolicies.Count) anti-spam policy/policies have spam filter bypasses configured:`n`n"
            $Result += ($FailedPolicies | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO143' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO143' -TenantFilter $Tenant
    }
}
