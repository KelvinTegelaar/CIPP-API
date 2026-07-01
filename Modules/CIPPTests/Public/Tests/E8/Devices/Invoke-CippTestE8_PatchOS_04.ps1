function Invoke-CippTestE8_PatchOS_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML2) - Quality update deferral is 14 days or less
    #>
    param($Tenant)

    $TestId = 'E8_PatchOS_04'
    $Name = 'Windows Update Ring quality update deferral is 14 days or less'

    try {
        $Legacy = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'
        $Rings = $Legacy | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' }

        if (-not $Rings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No `windowsUpdateForBusinessConfiguration` Update Ring policies cached for this tenant; quality deferral cannot be evaluated automatically.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Patch Operating Systems'
            return
        }

        $Bad = foreach ($R in $Rings) {
            $Defer = $R.qualityUpdatesDeferralPeriodInDays
            if ($null -ne $Defer -and $Defer -gt 14) {
                [pscustomobject]@{ Ring = $R.displayName; Deferral = $Defer }
            }
        }

        if (-not $Bad) {
            $Status = 'Passed'
            $Result = "All $($Rings.Count) Update Ring policy/policies defer quality updates by 14 days or less."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Bad.Count) Update Ring policy/policies defer quality updates by more than 14 days:`n`n| Ring | Deferral (days) |`n| :--- | :-------------: |`n")
            foreach ($B in $Bad) { $null = $Sb.Append("| $($B.Ring) | $($B.Deferral) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Patch Operating Systems'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML2 - Patch Operating Systems'
    }
}
