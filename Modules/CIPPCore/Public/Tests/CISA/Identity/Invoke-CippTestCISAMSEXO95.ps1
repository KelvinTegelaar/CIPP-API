function Invoke-CippTestCISAMSEXO95 {
    <#
    .SYNOPSIS
    Tests MS.EXO.9.5 - At a minimum, click-to-run files SHOULD be blocked

    .DESCRIPTION
    Checks if malware filter policies block click-to-run executables (.exe, .cmd, .vbe)

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Click-to-run files SHOULD be blocked' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO95' -TenantFilter $Tenant
            return
        }

        $RequiredBlockedTypes = @('cmd', 'exe', 'vbe')
        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $MalwarePolicies) {
            if (-not $Policy.EnableFileFilter) {
                # Policy doesn't have file filtering enabled at all
                $FailedPolicies.Add([PSCustomObject]@{
                        'Policy Name'         = $Policy.Name
                        'File Filter Enabled' = $false
                        'Issue'               = 'File filtering not enabled'
                    })
                continue
            }

            # Check if required types are blocked
            $BlockedTypes = $Policy.FileTypes
            $MissingTypes = $RequiredBlockedTypes | Where-Object { $_ -notin $BlockedTypes }

            if ($MissingTypes) {
                $FailedPolicies.Add([PSCustomObject]@{
                        'Policy Name'           = $Policy.Name
                        'File Filter Enabled'   = $true
                        'Missing Blocked Types' = ($MissingTypes -join ', ')
                    })
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = '✅ **Pass**: All malware filter policies block click-to-run files (.exe, .cmd, .vbe).'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) malware filter policy/policies do not properly block click-to-run executables:`n`n"
            $Result += "| Policy Name | File Filter Enabled | Missing Blocked Types |`n"
            $Result += "| :---------- | :------------------ | :-------------------- |`n"
            foreach ($Policy in $FailedPolicies) {
                $fileFilterValue = if ($Policy.'File Filter Enabled') { $Policy.'File Filter Enabled' } else { $Policy.'Issue' }
                $missingTypes = if ($Policy.'Missing Blocked Types') { $Policy.'Missing Blocked Types' } else { 'N/A' }
                $Result += "| $($Policy.'Policy Name') | $fileFilterValue | $missingTypes |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO95' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Click-to-run files SHOULD be blocked' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Click-to-run files SHOULD be blocked' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO95' -TenantFilter $Tenant
    }
}
