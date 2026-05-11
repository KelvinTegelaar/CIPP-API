function Invoke-CippTestCIS_4_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (4.2) - Device enrollment for personally owned devices SHALL be blocked by default
    #>
    param($Tenant)

    try {
        $Enrollment = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceEnrollmentConfigurations'

        if (-not $Enrollment) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'IntuneDeviceEnrollmentConfigurations cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Device enrollment for personally owned devices is blocked by default' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
            return
        }

        $DefaultPlatform = $Enrollment | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration' -and $_.priority -eq 0 -or $_.displayName -eq 'All Users' } | Select-Object -First 1
        if (-not $DefaultPlatform) { $DefaultPlatform = $Enrollment | Where-Object { $_.PSObject.Properties.Name -contains 'androidRestriction' } | Select-Object -First 1 }

        if (-not $DefaultPlatform) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Default Device Platform Restriction policy not found in cache.' -Risk 'Medium' -Name 'Device enrollment for personally owned devices is blocked by default' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
            return
        }

        $Failures = @()
        foreach ($P in @('androidForWorkRestriction', 'androidRestriction', 'iosRestriction', 'macOSRestriction', 'windowsRestriction')) {
            $r = $DefaultPlatform.$P
            if ($r -and $r.personalDeviceEnrollmentBlocked -ne $true -and $r.platformBlocked -ne $true) {
                $Failures += "$P : personal enrollment NOT blocked"
            }
        }

        if ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'All platforms block personally-owned device enrollment in the default policy.'
        } else {
            $Status = 'Failed'
            $Result = "Personal enrollment is allowed for one or more platforms in the default Device Platform Restriction policy:`n`n"
            $Result += ($Failures | ForEach-Object { "- $_" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Device enrollment for personally owned devices is blocked by default' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Device enrollment for personally owned devices is blocked by default' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    }
}
