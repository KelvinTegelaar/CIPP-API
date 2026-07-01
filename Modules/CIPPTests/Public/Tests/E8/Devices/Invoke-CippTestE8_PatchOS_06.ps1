function Invoke-CippTestE8_PatchOS_06 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML3) - BitLocker / disk encryption is required by compliance policy
    #>
    param($Tenant)

    $TestId = 'E8_PatchOS_06'
    $Name = 'Compliance policy requires storage to be encrypted (BitLocker)'

    try {
        $Compliance = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies'
        if (-not $Compliance) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Intune compliance policies cached for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Patch Operating Systems'
            return
        }

        $Win = $Compliance | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windows10CompliancePolicy' }
        $WithEnc = $Win | Where-Object { $_.bitLockerEnabled -eq $true -or $_.storageRequireEncryption -eq $true }
        $Assigned = $WithEnc | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }

        if ($Assigned) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Passed' -ResultMarkdown "$($Assigned.Count) Windows compliance policy/policies require encryption (BitLocker) and are assigned." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Patch Operating Systems'
        } elseif ($WithEnc) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Encryption is required by $($WithEnc.Count) compliance policy/policies but none are assigned." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Patch Operating Systems'
        } else {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows compliance policy requires storage encryption / BitLocker.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Patch Operating Systems'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - Patch Operating Systems'
    }
}
