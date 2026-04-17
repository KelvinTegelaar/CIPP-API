function Invoke-CippTestZTNA24568 {
    <#
    .SYNOPSIS
    Platform SSO is configured to strengthen authentication on macOS devices
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24568' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Platform SSO is configured to strengthen authentication on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Tenant'
            return
        }

        $MacOSPolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*macOS*' -and
            $_.technologies -like '*mdm*' -and
            $_.technologies -like '*appleRemoteManagement*'
        }

        if (-not $MacOSPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24568' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No macOS policies found' -Risk 'Medium' -Name 'Platform SSO is configured to strengthen authentication on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Tenant'
            return
        }

        $SSOPolicies = $MacOSPolicies | Where-Object {
            $children = $_.settings.settingInstance.groupSettingCollectionValue.children
            $extensionIdSetting = $children | Where-Object {
                $_.settingDefinitionId -eq 'com.apple.extensiblesso_extensionidentifier'
            }
            $extensionValue = $extensionIdSetting.simpleSettingValue.value
            $extensionValue -eq 'com.microsoft.CompanyPortalMac.ssoextension'
        }

        if (-not $SSOPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24568' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No macOS SSO policies configured with Microsoft Company Portal extension' -Risk 'Medium' -Name 'Platform SSO is configured to strengthen authentication on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Tenant'
            return
        }

        $AssignedSSOPolicies = $SSOPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedSSOPolicies) {
            $Status = 'Passed'
            $Result = "macOS SSO policies are configured and assigned. Found $($AssignedSSOPolicies.Count) assigned policy/policies"
        } else {
            $Status = 'Failed'
            $Result = "macOS SSO policy exists but is not assigned. Found $($SSOPolicies.Count) unassigned policy/policies"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24568' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Platform SSO is configured to strengthen authentication on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Tenant'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24568' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Platform SSO is configured to strengthen authentication on macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Tenant'
    }
}
