function Invoke-CippTestSMB1001_1_3 {
    <#
    .SYNOPSIS
    Tests SMB1001 (1.3) - Install antivirus software on all organization devices

    .DESCRIPTION
    Verifies an Intune endpoint security antivirus configuration policy exists and is assigned.
    SMB1001 1.3 requires actively-updated antivirus on workstations and laptops.
    #>
    param($Tenant)

    $TestId = 'SMB1001_1_3'
    $Name = 'Antivirus is installed and configured on all devices'

    try {
        $ConfigurationPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'

        if (-not $ConfigurationPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing Intune licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AVPolicies = @($ConfigurationPolicies | Where-Object {
                $_.templateReference -and $_.templateReference.templateFamily -eq 'endpointSecurityAntivirus'
            })

        if ($AVPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No endpoint security antivirus configuration policies found in Intune.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
            return
        }

        $AssignedPolicies = @($AVPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })

        if ($AssignedPolicies.Count -gt 0) {
            $Status = 'Passed'
            $TableRows = foreach ($P in $AVPolicies) {
                $A = if ($P.assignments -and $P.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $Plat = if ($P.platforms) { $P.platforms } else { 'unknown' }
                "| $($P.name) | $Plat | $A |"
            }
            $Result = (@(
                    "$($AssignedPolicies.Count) of $($AVPolicies.Count) antivirus policy/policies are assigned."
                    ''
                    '| Policy Name | Platform | Assigned |'
                    '| :---------- | :------- | :------- |'
                ) + $TableRows) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "Antivirus policies exist but none are assigned. Found $($AVPolicies.Count) unassigned policy/policies."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device'
    }
}
