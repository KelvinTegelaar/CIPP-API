function Invoke-CippTestE8_PatchOS_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Operating Systems, ML1) - All managed Windows devices run a supported OS build
    #>
    param($Tenant)

    $TestId = 'E8_PatchOS_02'
    $Name = 'All managed Windows devices run a supported Windows build (Win10 22H2 / Win11 22H2+)'

    try {
        $Devices = Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDevices'
        if (-not $Devices) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No ManagedDevices cached for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Patch Operating Systems'
            return
        }

        $Windows = $Devices | Where-Object { $_.operatingSystem -eq 'Windows' }
        if (-not $Windows) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Windows managed devices found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Patch Operating Systems'
            return
        }

        # Win10 22H2 = 19045.x ; Win11 22H2 = 22621.x ; Win11 23H2 = 22631.x ; Win11 24H2 = 26100.x
        $Unsupported = foreach ($D in $Windows) {
            $V = $D.osVersion
            if (-not $V) { continue }
            $parts = $V.Split('.')
            if ($parts.Count -lt 3) { continue }
            $build = [int]$parts[2]
            $Reason = $null
            if ($build -lt 19045) { $Reason = 'Windows 10 build < 22H2 (out of support)' }
            elseif ($build -ge 20000 -and $build -lt 22621) { $Reason = 'Windows 11 build < 22H2 (out of support)' }
            if ($Reason) { [pscustomobject]@{ Device = $D.deviceName; OSVersion = $V; Reason = $Reason } }
        }

        if (-not $Unsupported) {
            $Status = 'Passed'
            $Result = "All $($Windows.Count) Windows device(s) run a supported build."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Unsupported.Count) of $($Windows.Count) Windows device(s) are on unsupported builds:`n`n| Device | OS version | Reason |`n| :----- | :--------- | :----- |`n")
            foreach ($U in ($Unsupported | Select-Object -First 50)) { $null = $Sb.Append("| $($U.Device) | $($U.OSVersion) | $($U.Reason) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Patch Operating Systems'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML1 - Patch Operating Systems'
    }
}
