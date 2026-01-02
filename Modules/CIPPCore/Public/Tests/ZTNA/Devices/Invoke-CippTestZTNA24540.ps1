function Invoke-CippTestZTNA24540 {
    <#
    .SYNOPSIS
    Windows Firewall policies protect against unauthorized network access
    #>
    param($Tenant)
    #Tested - Device
    try {
        $ConfigurationPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24540' -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Windows Firewall policies protect against unauthorized network access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $FirewallPolicies = $ConfigurationPolicies | Where-Object {
            $_.templateReference -and $_.templateReference.templateFamily -eq 'endpointSecurityFirewall'
        }

        if ($FirewallPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24540' -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Windows Firewall configuration policies found' -Risk 'High' -Name 'Windows Firewall policies protect against unauthorized network access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AssignedPolicies = $FirewallPolicies | Where-Object {
            $_.assignments -and $_.assignments.Count -gt 0
        }

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $ResultLines = @(
                'At least one Windows Firewall policy is created and assigned to a group.'
                ''
                '**Windows Firewall Configuration Policies:**'
                ''
                '| Policy Name | Status | Assignment Count |'
                '| :---------- | :----- | :--------------- |'
            )

            foreach ($Policy in $FirewallPolicies) {
                $PolicyStatus = if ($Policy.assignments -and $Policy.assignments.Count -gt 0) {
                    '✅ Assigned'
                } else {
                    '❌ Not assigned'
                }
                $AssignmentCount = if ($Policy.assignments) { $Policy.assignments.Count } else { 0 }
                $ResultLines += "| $($Policy.name) | $PolicyStatus | $AssignmentCount |"
            }

            $Result = $ResultLines -join "`n"
        } else {
            $Status = 'Failed'
            $ResultLines = @(
                'There are no firewall policies assigned to any groups.'
                ''
                '**Windows Firewall Configuration Policies (Unassigned):**'
                ''
            )

            foreach ($Policy in $FirewallPolicies) {
                $ResultLines += "- $($Policy.name)"
            }

            $Result = $ResultLines -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24540' -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Windows Firewall policies protect against unauthorized network access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA24540' -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Windows Firewall policies protect against unauthorized network access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device'
    }
}
