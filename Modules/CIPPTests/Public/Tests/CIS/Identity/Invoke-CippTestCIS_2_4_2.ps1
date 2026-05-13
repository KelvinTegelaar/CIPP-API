function Invoke-CippTestCIS_2_4_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.4.2) - Priority accounts SHALL have 'Strict protection' presets applied
    #>
    param($Tenant)

    try {
        $Preset = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoPresetSecurityPolicy'

        if (-not $Preset) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name "Priority accounts have 'Strict protection' presets applied" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
            return
        }

        $Strict = $Preset | Where-Object { $_.Identity -like '*Strict Preset Security Policy*' -and $_.State -eq 'Enabled' }

        if ($Strict) {
            $Status = 'Passed'
            $Result = "Strict preset security policy is enabled. Confirm priority accounts are scoped into the rule (`Get-EOPProtectionPolicyRule -Identity 'Strict Preset Security Policy'`)."
        } else {
            $Status = 'Failed'
            $Result = 'Strict preset security policy is not enabled. Enable it in the Microsoft 365 Defender portal and scope priority accounts into the rule.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "Priority accounts have 'Strict protection' presets applied" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_4_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "Priority accounts have 'Strict protection' presets applied" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
    }
}
