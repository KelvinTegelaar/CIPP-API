function Invoke-CippTestSMB1001_1_2 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.2) - Install and configure a firewall on all devices

    .DESCRIPTION
    Verifies an Intune endpoint security firewall configuration policy exists and is assigned.
    SMB1001 1.2 requires firewalls on every device that connects to the Internet, including
    personal devices used for work.
    #>
    param($Tenant)

    $TestId = 'SMB1001_1_2'
    $Name = 'Firewall is configured on all devices'

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing Intune licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $FirewallPolicies = @($ConfigurationPolicies | Where-Object {
                $_.templateReference -and $_.templateReference.templateFamily -eq 'endpointSecurityFirewall'
            })

        if ($FirewallPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No endpoint security firewall configuration policies found in Intune.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AssignedPolicies = @($FirewallPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $TableRows = foreach ($P in $FirewallPolicies) {
                $A = if ($P.assignments -and $P.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                "| $($P.name) | $A |"
            }
            $Result = (@(
                    "$($AssignedPolicies.Count) of $($FirewallPolicies.Count) firewall policy/policies are assigned."
                    ''
                    '| Policy Name | Assigned |'
                    '| :---------- | :------- |'
                ) + $TableRows) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "Firewall policies exist but none are assigned. Found $($FirewallPolicies.Count) unassigned policy/policies."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
