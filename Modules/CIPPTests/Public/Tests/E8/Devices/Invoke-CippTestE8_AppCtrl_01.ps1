function Invoke-CippTestE8_AppCtrl_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Application Control, ML1) - Application control is implemented on workstations
    #>
    param($Tenant)

    $TestId = 'E8_AppCtrl_01'
    $Name = 'Application control (WDAC / Smart App Control / AppLocker) is configured for Windows endpoints'

    try {
        $ConfigPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Intune Configuration Policies cached for this tenant.' -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Application Control'
            return
        }

        $AppControlPolicies = $ConfigPolicies | Where-Object {
            $ids = $_.settings.settingInstance.settingDefinitionId
            ($ids -match 'applicationcontrol') -or ($ids -match 'smartappcontrol') -or ($ids -match 'applocker')
        }
        $Assigned = $AppControlPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 }

        if ($Assigned) {
            $Status = 'Passed'
            $Result = "$($Assigned.Count) application-control policy/policies (WDAC/Smart App Control/AppLocker) are configured and assigned."
        } elseif ($AppControlPolicies) {
            $Status = 'Failed'
            $Result = "$($AppControlPolicies.Count) application-control policy/policies exist but none are assigned."
        } else {
            $Status = 'Failed'
            $Result = 'No WDAC, Smart App Control, or AppLocker configuration policy is deployed via Intune.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Application Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML1 - Application Control'
    }
}
