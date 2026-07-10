function Invoke-CippTestE8_PatchOS_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML1) - A device compliance policy enforces a minimum OS version
    #>
    param($Tenant)

    $TestId = 'E8_PatchOS_03'
    $Name = 'A device compliance policy enforces a minimum Windows OS version'

    try {
        $Compliance = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies'
        if (-not $Compliance) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Intune compliance policies cached for this tenant.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
            return
        }

        $Win = $Compliance | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10CompliancePolicy' }
        $WithMinVersion = $Win | Where-Object { $_.osMinimumVersion }
        $Assigned = $WithMinVersion | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }

        if ($Assigned) {
            $Status = 'Passed'
            $Result = "$($Assigned.Count) Windows compliance policy/policies enforce a minimum OS version (e.g. $($Assigned[0].osMinimumVersion))."
        } elseif ($WithMinVersion) {
            $Status = 'Failed'
            $Result = "$($WithMinVersion.Count) Windows compliance policy/policies set a minimum OS version but none are assigned."
        } else {
            $Status = 'Failed'
            $Result = 'No Windows compliance policy enforces a minimum OS version (`osMinimumVersion`).'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
    }
}
