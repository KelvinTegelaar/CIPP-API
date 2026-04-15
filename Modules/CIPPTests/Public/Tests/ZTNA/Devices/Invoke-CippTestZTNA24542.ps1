function Invoke-CippTestZTNA24542 {
    <#
    .SYNOPSIS
    Compliance policies protect macOS devices
    #>
    param($Tenant)

    $TestId = 'ZTNA24542'
    #Tested - Device
    try {
        $IntunePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies'

        if (-not $IntunePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Compliance policies protect macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $MacOSPolicies = @($IntunePolicies | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.macOSCompliancePolicy' })
        $AssignedPolicies = @($MacOSPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ At least one macOS compliance policy exists and is assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No macOS compliance policy exists or none are assigned.`n`n"
        }

        $ResultMarkdown += "## macOS Compliance Policies`n`n"
        $ResultMarkdown += "| Policy Name | Assigned |`n"
        $ResultMarkdown += "| :---------- | :------- |`n"

        foreach ($policy in $MacOSPolicies) {
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $ResultMarkdown += "| $($policy.displayName) | $assigned |`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Compliance policies protect macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Compliance policies protect macOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
