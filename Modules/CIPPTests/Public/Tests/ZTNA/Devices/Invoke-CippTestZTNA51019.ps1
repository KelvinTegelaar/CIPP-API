function Invoke-CippTestZTNA51019 {
    <#
    .SYNOPSIS
    MAM app access timeout and re-authentication are enforced after idle period
    #>
    param($Tenant)

    $TestId = 'ZTNA51019'
    $Name = 'MAM app access timeout and re-authentication are enforced after idle period'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $Devices = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDevices')
        $IosDeviceCount = $Devices.Where({ $_.operatingSystem -in @('iOS', 'iPadOS') }).Count
        $AndroidDeviceCount = $Devices.Where({ $_.operatingSystem -eq 'Android' }).Count
        if ($IosDeviceCount -eq 0 -and $AndroidDeviceCount -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No iOS / iPadOS or Android devices are enrolled in this tenant (or managed devices have not been collected yet).' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneAppProtectionManagedAppPolicies').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'IntuneAppProtectionManagedAppPolicies' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. App protection policies have not been collected yet.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $Platforms = foreach ($Definition in @(@('iOS / iPadOS', 'iosManagedAppProtection', $IosDeviceCount), @('Android', 'androidManagedAppProtection', $AndroidDeviceCount))) {
            $OdataType = $Definition[1]
            $Rows = foreach ($Policy in $Policies.Where({ $_.URLName -eq $OdataType })) {
                $Qualifies = $false
                if ($Policy.isAssigned -eq $true -and -not [string]::IsNullOrEmpty($Policy.periodOnlineBeforeAccessCheck) -and ($Policy.pinRequired -eq $true -or $Policy.organizationalCredentialsRequired -eq $true)) {
                    try {
                        $Qualifies = [System.Xml.XmlConvert]::ToTimeSpan($Policy.periodOnlineBeforeAccessCheck).TotalMinutes -le 30
                    } catch {
                        $Qualifies = $false
                    }
                }
                [PSCustomObject]@{ Policy = $Policy; Pass = $Qualifies }
            }
            [PSCustomObject]@{
                Label       = $Definition[0]
                OdataType   = $OdataType
                DeviceCount = $Definition[2]
                Rows        = @($Rows)
            }
        }
        $Passed = $Platforms.Where({ $_.DeviceCount -gt 0 -and $_.Rows.Where({ $_.Pass }).Count -eq 0 }).Count -eq 0

        $Summary = if ($Passed) {
            '✅ For every in-scope mobile platform with enrolled devices, assigned MAM App Protection Policies recheck app access requirements within 30 minutes and enforce an access gate such as app PIN or organizational credentials.'
        } else {
            '❌ One or more in-scope mobile platforms (iOS / iPadOS, Android) has no assigned App Protection Policy that enforces a 30-minute-or-less app access recheck window with an app PIN or organizational credential gate.'
        }
        $OverallText = if ($Passed) { 'Pass' } else { 'Fail' }
        $PortalLink = 'https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsMenu/~/protection'
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`nOverall: $OverallText`n")
        foreach ($Platform in $Platforms) {
            $null = $ResultMarkdown.Append("`n### [$($Platform.Label) App Protection Policies — Access Recheck Enforcement]($PortalLink)`n`n")
            if ($Platform.DeviceCount -eq 0) {
                $null = $ResultMarkdown.Append("**Status: Skipped** — No $($Platform.Label) devices enrolled in this tenant.`n")
                continue
            }
            $QualifyCount = $Platform.Rows.Where({ $_.Pass }).Count
            $PlatformText = if ($QualifyCount -gt 0) { 'Pass' } else { 'Fail' }
            $null = $ResultMarkdown.Append("**Status: $PlatformText** — $($Platform.DeviceCount) $($Platform.Label) devices enrolled; $QualifyCount of $($Platform.Rows.Count) policies qualify.`n`n| Policy name | Online recheck | App PIN required | Organizational credentials required | Assigned | Status |`n| :---------- | :------------- | :--------------- | :---------------------------------- | :------- | :----- |`n")
            foreach ($Row in $Platform.Rows.Where({ $true }, 'First', 10)) {
                $Policy = $Row.Policy
                $OnlineRecheck = if ([string]::IsNullOrEmpty($Policy.periodOnlineBeforeAccessCheck)) { '—' } else { $Policy.periodOnlineBeforeAccessCheck }
                $Pin = if ($Policy.pinRequired -eq $true) { '✅ Yes' } else { '❌ No' }
                $OrgCreds = if ($Policy.organizationalCredentialsRequired -eq $true) { '✅ Yes' } else { '❌ No' }
                $Assigned = if ($Policy.isAssigned -eq $true) { '✅ Yes' } else { '❌ No' }
                $RowStatus = if ($Row.Pass) { '✅ Pass' } else { '❌ Fail' }
                $PolicyLink = 'https://intune.microsoft.com/#view/Microsoft_Intune/PolicyInstanceMenuBlade/~/0/policyId/{0}/policyOdataType/%23microsoft.graph.{1}/policyName/{2}' -f $Policy.id, $Platform.OdataType, [Uri]::EscapeDataString([string]$Policy.displayName)
                $null = $ResultMarkdown.Append("| [$($Policy.displayName)]($PolicyLink) | $OnlineRecheck | $Pin | $OrgCreds | $Assigned | $RowStatus |`n")
            }
            if ($Platform.Rows.Count -gt 10) {
                $null = $ResultMarkdown.Append("| ... and $($Platform.Rows.Count - 10) more policies | | | | | |`n")
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Devices'
    }
}
