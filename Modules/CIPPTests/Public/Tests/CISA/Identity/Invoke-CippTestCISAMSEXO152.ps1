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
        $SafeLinksPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $SafeLinksPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSafeLinksPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Real-time suspicious URL scanning SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO152' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = $SafeLinksPolicies | Where-Object { -not $_.ScanUrls }

        if ($FailedPolicies.Count -eq 0) {
            $Result = [System.Text.StringBuilder]::new("✅ **Pass**: All $($SafeLinksPolicies.Count) Safe Links policy/policies have real-time URL scanning enabled.")
            $Status = 'Passed'
        } else {
            $Result = [System.Text.StringBuilder]::new("❌ **Fail**: $($FailedPolicies.Count) of $($SafeLinksPolicies.Count) Safe Links policy/policies do not have real-time URL scanning enabled:`n`n")
            $null = $Result.Append("| Policy Name | Scan URLs |`n")
            $null = $Result.Append("| :---------- | :-------- |`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Name) | $($Policy.ScanUrls) |`n")
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO152' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Real-time suspicious URL scanning SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Real-time suspicious URL scanning SHOULD be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO152' -TenantFilter $Tenant
    }
}
