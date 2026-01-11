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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO112' -TenantFilter $Tenant
            return
        }

        $PoliciesWithTips = $PresetPolicies | Where-Object {
            ($_.EnableSimilarUsersSafetyTips -eq $true) -or
            ($_.EnableSimilarDomainsSafetyTips -eq $true) -or
            ($_.EnableUnusualCharactersSafetyTips -eq $true)
        }

        if ($PoliciesWithTips.Count -gt 0) {
            $ResultTable = $PoliciesWithTips | ForEach-Object {
                [PSCustomObject]@{
                    'Policy' = $_.Identity
                    'Similar Users Tips' = $_.EnableSimilarUsersSafetyTips
                    'Similar Domains Tips' = $_.EnableSimilarDomainsSafetyTips
                    'Unusual Characters Tips' = $_.EnableUnusualCharactersSafetyTips
                }
            }

            $Result = "✅ **Pass**: $($PoliciesWithTips.Count) policy/policies have impersonation safety tips enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: No policies found with impersonation safety tips enabled.`n`n"
            $Result += "Enable safety tips in preset security policies to warn users about potential impersonation."
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO112' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO112' -TenantFilter $Tenant
    }
}
