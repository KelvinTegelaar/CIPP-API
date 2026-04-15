function Invoke-CippTestZTNA24543 {
    <#
    .SYNOPSIS
    Compliance policies protect iOS/iPadOS devices
    #>
    param($Tenant)

    $TestId = 'ZTNA24543'
    #Tested - Device

    try {
        $IntunePolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneDeviceCompliancePolicies'

        if (-not $IntunePolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Compliance policies protect iOS/iPadOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $iOSPolicies = @($IntunePolicies | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.iosCompliancePolicy' })
        $AssignedPolicies = @($iOSPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ At least one iOS/iPadOS compliance policy exists and is assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No iOS/iPadOS compliance policy exists or none are assigned.`n`n"
        }

        $ResultMarkdown += "## iOS/iPadOS Compliance Policies`n`n"
        $ResultMarkdown += "| Policy Name | Assigned |`n"
        $ResultMarkdown += "| :---------- | :------- |`n"

        foreach ($policy in $iOSPolicies) {
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $ResultMarkdown += "| $($policy.displayName) | $assigned |`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Compliance policies protect iOS/iPadOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Compliance policies protect iOS/iPadOS devices' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
