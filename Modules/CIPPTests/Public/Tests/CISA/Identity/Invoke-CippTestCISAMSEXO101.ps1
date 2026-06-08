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
        $MalwarePolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $MalwarePolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Emails SHALL be filtered by attachment file types' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO101' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $MalwarePolicies | Where-Object { -not $_.EnableFileFilter }

        if ($FailedPolicies.Count -eq 0) {
            $Result = [System.Text.StringBuilder]::new("✅ **Pass**: All $($MalwarePolicies.Count) malware filter policy/policies have file filtering enabled.")
            $Status = 'Passed'
        } else {
            $Result = [System.Text.StringBuilder]::new("❌ **Fail**: $($FailedPolicies.Count) of $($MalwarePolicies.Count) malware filter policy/policies do not have file filtering enabled:`n`n")
            $null = $Result.Append("| Policy Name | File Filter Enabled |`n")
            $null = $Result.Append("| :---------- | :------------------ |`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Name) | $($Policy.EnableFileFilter) |`n")
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO101' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Emails SHALL be filtered by attachment file types' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Emails SHALL be filtered by attachment file types' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO101' -TenantFilter $Tenant
    }
}
