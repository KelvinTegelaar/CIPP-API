function Invoke-CippTestZTNA24564 {
    <#
    .SYNOPSIS
    Local account usage on Windows is restricted to reduce unauthorized access
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24564' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Local account usage on Windows is restricted to reduce unauthorized access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $WindowsPolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*windows10*'
        }

        if (-not $WindowsPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24564' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows policies found' -Risk 'High' -Name 'Local account usage on Windows is restricted to reduce unauthorized access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $LocalUsersGroupsPolicies = $WindowsPolicies | Where-Object {
            $settingIds = $_.settings.settingInstance.settingDefinitionId
            if ($settingIds -is [string]) {
                $settingIds -eq 'device_vendor_msft_policy_config_localusersandgroups_configure'
            } else {
                $settingIds -contains 'device_vendor_msft_policy_config_localusersandgroups_configure'
            }
        }

        if (-not $LocalUsersGroupsPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24564' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Local Users and Groups policy configured' -Risk 'High' -Name 'Local account usage on Windows is restricted to reduce unauthorized access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AssignedPolicies = $LocalUsersGroupsPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies) {
            $Status = 'Passed'
            $Result = "At least one Local Users and Groups policy is configured and assigned. Found $($AssignedPolicies.Count) assigned policy/policies"
        } else {
            $Status = 'Failed'
            $Result = "Local Users and Groups policy exists but is not assigned. Found $($LocalUsersGroupsPolicies.Count) unassigned policy/policies"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24564' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Local account usage on Windows is restricted to reduce unauthorized access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24564' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Local account usage on Windows is restricted to reduce unauthorized access' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
