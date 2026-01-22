function Invoke-CippTestZTNA24575 {
    <#
    .SYNOPSIS
    Defender Antivirus policies protect Windows devices from malware
    #>
    param($Tenant)
    #Tested - Device

    try {
        $ConfigPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24575' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Defender Antivirus policies protect Windows devices from malware' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $MdmSensePolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*windows10*' -and
            $_.technologies -like '*mdm*' -and
            $_.technologies -like '*microsoftSense*'
        }

        if (-not $MdmSensePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24575' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows Defender policies found' -Risk 'High' -Name 'Defender Antivirus policies protect Windows devices from malware' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $AVPolicies = $MdmSensePolicies | Where-Object {
            $_.templateReference.templateFamily -eq 'endpointSecurityAntivirus'
        }

        if (-not $AVPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24575' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows Defender Antivirus policies found' -Risk 'High' -Name 'Defender Antivirus policies protect Windows devices from malware' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
            return
        }

        $AssignedPolicies = $AVPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies) {
            $Status = 'Passed'
            $Result = "Windows Defender Antivirus policies are configured and assigned. Found $($AssignedPolicies.Count) assigned policy/policies"
        } else {
            $Status = 'Failed'
            $Result = "Windows Defender Antivirus policies exist but are not assigned. Found $($AVPolicies.Count) unassigned policy/policies"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24575' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Defender Antivirus policies protect Windows devices from malware' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24575' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Defender Antivirus policies protect Windows devices from malware' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Device'
    }
}
