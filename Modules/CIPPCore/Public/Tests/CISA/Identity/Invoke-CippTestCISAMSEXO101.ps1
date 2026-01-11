function Invoke-CippTestCISAMSEXO101 {
    <#
    .SYNOPSIS
    Tests MS.EXO.10.1 - Emails SHALL be filtered by attachment file types

    .DESCRIPTION
    Checks if malware filter policies have file filtering enabled

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $MalwarePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicy'

        if (-not $MalwarePolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO101' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $MalwarePolicies | Where-Object { -not $_.EnableFileFilter }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($MalwarePolicies.Count) malware filter policy/policies have file filtering enabled."
            $Status = 'Pass'
        } else {
            $ResultTable = foreach ($Policy in $FailedPolicies) {
                [PSCustomObject]@{
                    'Policy Name' = $Policy.Name
                    'File Filter Enabled' = $Policy.EnableFileFilter
                }
            }

            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($MalwarePolicies.Count) malware filter policy/policies do not have file filtering enabled:`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO101' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO101' -TenantFilter $Tenant
    }
}
