function Invoke-CippTestZTNA24549 {
    <#
    .SYNOPSIS
    Data on Android is protected by app protection policies
    #>
    param($Tenant)

    $TestId = 'ZTNA24549'
    #Tested - Device

    try {
        $AndroidPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'IntuneAndroidAppProtectionPolicies'

        if (-not $AndroidPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $AssignedPolicies = @($AndroidPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ At least one Android app protection policy exists and is assigned.`n`n"
        } else {
            $ResultMarkdown = "❌ No Android app protection policy exists or none are assigned.`n`n"
        }

        $ResultMarkdown += "## Android App Protection Policies`n`n"
        $ResultMarkdown += "| Policy Name | Assigned |`n"
        $ResultMarkdown += "| :---------- | :------- |`n"

        foreach ($policy in $AndroidPolicies) {
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $ResultMarkdown += "| $($policy.displayName) | $assigned |`n"
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
