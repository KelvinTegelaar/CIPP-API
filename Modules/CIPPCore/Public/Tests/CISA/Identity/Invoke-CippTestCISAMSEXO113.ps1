function Invoke-CippTestCISAMSEXO113 {
    <#
    .SYNOPSIS
    Tests MS.EXO.11.3 - Mailbox intelligence SHALL be enabled

    .DESCRIPTION
    Checks if mailbox intelligence and impersonation protection are enabled in preset security policies

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO113' -TenantFilter $Tenant
            return
        }

        $PoliciesWithIntelligence = $PresetPolicies | Where-Object {
            ($_.EnableMailboxIntelligence -eq $true) -and
            ($_.EnableMailboxIntelligenceProtection -eq $true)
        }

        if ($PoliciesWithIntelligence.Count -gt 0) {
            $ResultTable = $PoliciesWithIntelligence | ForEach-Object {
                [PSCustomObject]@{
                    'Policy'                  = $_.Identity
                    'Mailbox Intelligence'    = $_.EnableMailboxIntelligence
                    'Intelligence Protection' = $_.EnableMailboxIntelligenceProtection
                    'State'                   = $_.State
                }
            }

            $Result = "✅ **Pass**: $($PoliciesWithIntelligence.Count) policy/policies have mailbox intelligence enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: No policies found with mailbox intelligence enabled.`n`n"
            $Result += 'Enable mailbox intelligence in preset security policies for AI-powered impersonation protection.'
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO113' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO113' -TenantFilter $Tenant
    }
}
