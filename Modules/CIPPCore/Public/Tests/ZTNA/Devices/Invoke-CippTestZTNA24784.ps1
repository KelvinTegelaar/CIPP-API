function Invoke-CippTestZTNA24784 {
    <#
    .SYNOPSIS
    Defender Antivirus policies protect macOS devices from malware
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24784' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Defender Antivirus policies protect macOS devices from malware' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $MdmMacOSSensePolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*macOS*' -and
            $_.technologies -like '*mdm*' -and
            $_.technologies -like '*microsoftSense*'
        }

        if (-not $MdmMacOSSensePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24784' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No macOS Defender policies found' -Risk 'High' -Name 'Defender Antivirus policies protect macOS devices from malware' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AVPolicies = $MdmMacOSSensePolicies | Where-Object {
            $_.templateReference.templateFamily -eq 'endpointSecurityAntivirus'
        }

        if (-not $AVPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24784' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Defender Antivirus policies for macOS found' -Risk 'High' -Name 'Defender Antivirus policies protect macOS devices from malware' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AssignedPolicies = $AVPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies) {
            $Status = 'Passed'
            $Result = "Defender Antivirus policies for macOS are configured and assigned. Found $($AssignedPolicies.Count) assigned policy/policies"
        } else {
            $Status = 'Failed'
            $Result = "Defender Antivirus policies for macOS exist but are not assigned. Found $($AVPolicies.Count) unassigned policy/policies"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24784' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Defender Antivirus policies protect macOS devices from malware' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24784' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Defender Antivirus policies protect macOS devices from malware' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
