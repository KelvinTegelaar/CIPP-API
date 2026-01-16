function Invoke-CippTestCISAMSEXO111 {
    <#
    .SYNOPSIS
    Tests MS.EXO.11.1 - Impersonation protection checks SHOULD be used

    .DESCRIPTION
    Checks if both standard and strict EOP/ATP preset security policies are enabled

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoPresetSecurityPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Impersonation protection checks SHOULD be used' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection' -TestId 'CISAMSEXO111' -TenantFilter $Tenant
            return
        }

        $StandardEOP = $PresetPolicies | Where-Object { $_.Identity -eq 'Standard Preset Security Policy' -and $_.State -eq 'Enabled' }
        $StrictEOP = $PresetPolicies | Where-Object { $_.Identity -eq 'Strict Preset Security Policy' -and $_.State -eq 'Enabled' }

        $StandardATP = $PresetPolicies | Where-Object { $_.Identity -like '*Preset Security Policy*' -and $_.ImpersonationProtectionState -eq 'Enabled' }

        $EnabledPolicies = @()
        if ($StandardEOP) { $EnabledPolicies += 'Standard EOP' }
        if ($StrictEOP) { $EnabledPolicies += 'Strict EOP' }
        if ($StandardATP) { $EnabledPolicies += "$($StandardATP.Count) ATP policy/policies with impersonation protection" }

        if ($EnabledPolicies.Count -gt 0) {
            $Result = "✅ **Pass**: Preset security policies with impersonation protection are enabled:`n`n"
            $Result += ($EnabledPolicies | ForEach-Object { "- $_" }) -join "`n"
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: No preset security policies with impersonation protection enabled.`n`n"
            $Result += "Enable Standard or Strict preset security policies to provide impersonation protection."
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO111' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Impersonation protection checks SHOULD be used' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Impersonation protection checks SHOULD be used' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection' -TestId 'CISAMSEXO111' -TenantFilter $Tenant
    }
}
