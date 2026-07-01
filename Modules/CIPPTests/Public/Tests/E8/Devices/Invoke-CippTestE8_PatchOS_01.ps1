function Invoke-CippTestE8_PatchOS_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML1) - A Windows Update Ring policy is configured and assigned
    #>
    param($Tenant)

    $TestId = 'E8_PatchOS_01'
    $Name = 'A Windows Update Ring policy is configured and assigned'

    try {
        $ConfigPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        $LegacyPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'

        $UpdateRings = @()
        if ($ConfigPolicies) {
            $UpdateRings += $ConfigPolicies | Where-Object {
                $ids = $_.settings.settingInstance.settingDefinitionId
                ($ids -match 'windowsupdate') -or ($ids -match 'update_ring')
            }
        }
        if ($LegacyPolicies) {
            $UpdateRings += $LegacyPolicies | Where-Object {
                $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration'
            }
        }

        if (-not $UpdateRings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows Update for Business / Update Ring configuration policy is deployed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
            return
        }

        $Assigned = $UpdateRings | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }
        if ($Assigned) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Passed' -ResultMarkdown "$($Assigned.Count) Windows Update Ring policy/policies are configured and assigned." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
        } else {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "$($UpdateRings.Count) Windows Update Ring policy/policies exist but none are assigned to any group/device." -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Operating Systems'
    }
}
