function Invoke-CippTestCISAMSEXO103 {
    <#
    .SYNOPSIS
    Tests MS.EXO.10.3 - Email scanning SHALL be capable of reviewing emails after delivery (ZAP)

    .DESCRIPTION
    Checks if Zero-hour Auto Purge (ZAP) is enabled for malware protection

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Email scanning SHALL be capable of reviewing emails after delivery' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO103' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $MalwarePolicies | Where-Object { -not $_.ZapEnabled }

        if ($FailedPolicies.Count -eq 0) {
            $Result = "✅ **Pass**: All $($MalwarePolicies.Count) malware filter policy/policies have ZAP (Zero-hour Auto Purge) enabled."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) of $($MalwarePolicies.Count) malware filter policy/policies do not have ZAP enabled:`n`n"
            $Result += "| Policy Name | ZAP Enabled |`n"
            $Result += "| :---------- | :---------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $Result += "| $($Policy.Name) | $($Policy.ZapEnabled) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO103' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Email scanning SHALL be capable of reviewing emails after delivery' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Email scanning SHALL be capable of reviewing emails after delivery' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO103' -TenantFilter $Tenant
    }
}
