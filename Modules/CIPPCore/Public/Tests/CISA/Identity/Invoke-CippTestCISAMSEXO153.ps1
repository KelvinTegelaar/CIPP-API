function Invoke-CippTestCISAMSEXO153 {
    <#
    .SYNOPSIS
    Tests MS.EXO.15.3 - User click tracking SHOULD be disabled

    .DESCRIPTION
    Checks if Safe Links policies have click tracking disabled for privacy

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Low' -Category 'Exchange Online' -TestId 'CISAMSEXO153' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { $_.TrackUserClicks -eq $true }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have click tracking disabled."
            $Status = 'Pass'
        } else {
            $ResultTable = foreach ($Policy in $FailedPolicies) {
                [PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'Track User Clicks' = $Policy.TrackUserClicks
                }
            }

            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies have click tracking enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO153' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Category 'Exchange Online' -TestId 'CISAMSEXO153' -TenantFilter $Tenant
    }
}
