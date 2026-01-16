function Invoke-CippTestZTNA24553 {
    <#
    .SYNOPSIS
    Windows Update policies are enforced to reduce risk from unpatched vulnerabilities
    #>
    param($Tenant)
    #Tested - Device

    $TestId = 'ZTNA24553'

    try {
        $IntunePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies'

        if (-not $IntunePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Windows Update policies are enforced to reduce risk from unpatched vulnerabilities' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $UpdatePolicies = @($IntunePolicies | Where-Object {
                $_.'@odata.type' -in @(
                    '#microsoft.graph.windowsUpdateForBusinessConfiguration',
                    '#microsoft.graph.windows10CompliancePolicy'
                )
            })

        $AssignedPolicies = @($UpdatePolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ Windows Update policies are configured and assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No Windows Update policies are configured or assigned.`n`n"
        }

        $ResultMarkdown += "## Windows Update Policies`n`n"
        $ResultMarkdown += "| Policy Name | Type | Assigned |`n"
        $ResultMarkdown += "| :---------- | :--- | :------- |`n"

        foreach ($policy in $UpdatePolicies) {
            $type = if ($policy.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration') { 'Update' } else { 'Compliance' }
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $ResultMarkdown += "| $($policy.displayName) | $type | $assigned |`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Windows Update policies are enforced to reduce risk from unpatched vulnerabilities' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Windows Update policies are enforced to reduce risk from unpatched vulnerabilities' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
