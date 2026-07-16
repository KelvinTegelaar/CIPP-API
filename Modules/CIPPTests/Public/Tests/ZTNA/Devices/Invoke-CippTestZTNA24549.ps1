function Invoke-CippTestZTNA24549 {
    <#
    .SYNOPSIS
    Data on Android is protected by app protection policies
    #>
    param($Tenant)

    $TestId = 'ZTNA24549'
    #Tested - Device

    try {
        # App protection policies for every platform live under one type; URLName carries the
        # Graph resource they came from and is the platform discriminator. This previously read
        # 'IntuneAndroidAppProtectionPolicies', a type no collector writes, so the test always skipped.
        $AllPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneAppProtectionManagedAppPolicies')

        # Only skip when the type itself is absent (no Intune licence, or collection has not run).
        if ($AllPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $AndroidPolicies = @($AllPolicies | Where-Object { $_.URLName -eq 'androidManagedAppProtection' })

        # Data exists but no Android policy at all — that is a genuine failure of this control, not
        # a missing-data skip.
        if ($AndroidPolicies.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "❌ No Android app protection policy exists in this tenant.`n`nApp protection policies were found for other platforms, so Intune data is being collected — there is simply no Android policy." -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $AssignedPolicies = @($AndroidPolicies | Where-Object { $_.assignments -and $_.assignments.Count -gt 0 })
        $Passed = $AssignedPolicies.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = [System.Text.StringBuilder]::new("✅ At least one Android app protection policy exists and is assigned.`n`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("❌ Android app protection policies exist but none are assigned.`n`n")
        }

        $null = $ResultMarkdown.Append("## Android App Protection Policies`n`n")
        $null = $ResultMarkdown.Append("| Policy Name | Assigned |`n")
        $null = $ResultMarkdown.Append("| :---------- | :------- |`n")

        foreach ($policy in $AndroidPolicies) {
            $assigned = if ($policy.assignments -and $policy.assignments.Count -gt 0) { '✅ Yes' } else { '❌ No' }
            $null = $ResultMarkdown.Append("| $($policy.displayName) | $assigned |`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Data on Android is protected by app protection policies' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
