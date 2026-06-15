function Invoke-CippTestZTNA24548 {
    <#
    .SYNOPSIS
    Data on iOS/iPadOS is protected by app protection policies
    #>
    param($Tenant)

    $TestId = 'ZTNA24548'
    #Tested - Device

    try {
        $IosPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneIosAppProtectionPolicies'

        if (-not $IosPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on iOS/iPadOS is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $AssignedPolicies = @($IosPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ At least one iOS app protection policy exists and is assigned.`n`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("❌ No iOS app protection policy exists or none are assigned.`n`n")
        }

        $null = $ResultMarkdown.Append("## iOS App Protection Policies`n`n")
        $null = $ResultMarkdown.Append("| Policy Name | Assigned |`n")
        $null = $ResultMarkdown.Append("| :---------- | :------- |`n")

        foreach ($policy in $IosPolicies) {
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $null = $ResultMarkdown.Append("| $($policy.displayName) | $assigned |`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Data on iOS/iPadOS is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on iOS/iPadOS is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
