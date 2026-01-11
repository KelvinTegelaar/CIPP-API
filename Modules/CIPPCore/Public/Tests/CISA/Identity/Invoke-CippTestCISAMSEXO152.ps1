function Invoke-CippTestCISAMSEXO152 {
    <#
    .SYNOPSIS
    Tests MS.EXO.15.2 - Real-time suspicious URL and file-link scanning SHOULD be enabled

    .DESCRIPTION
    Checks if Safe Links policies have real-time link scanning enabled

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO152' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { -not $_.ScanUrls }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have real-time URL scanning enabled."
            $Status = 'Pass'
        } else {
            $ResultTable = foreach ($Policy in $FailedPolicies) {
                [PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Scan URLs' = $Policy.ScanUrls
                }
            }

            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies do not have real-time URL scanning enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO152' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO152' -TenantFilter $Tenant
    }
}
