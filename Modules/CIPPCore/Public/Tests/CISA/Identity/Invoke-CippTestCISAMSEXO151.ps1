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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { -not $_.EnableSafeLinksForEmail }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have URL comparison with block-list enabled."
            $Status = 'Pass'
        } else {
            $ResultTable = foreach ($Policy in $FailedPolicies) {
                [PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Safe Links for Email' = $Policy.EnableSafeLinksForEmail
                }
            }

            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies do not have URL scanning enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO151' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO151' -TenantFilter $Tenant
    }
}
