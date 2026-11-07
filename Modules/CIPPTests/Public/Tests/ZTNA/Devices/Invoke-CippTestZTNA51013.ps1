function Invoke-CippTestZTNA51013 {
    <#
    .SYNOPSIS
    App Protection Policies block managed-app access when user re-authentication fails (disabled Entra ID accounts, blocked sign-ins, expired tokens)
    #>
    param($Tenant)

    $TestId = 'ZTNA51013'
    $Name = 'App Protection Policies block managed-app access when user re-authentication fails (disabled Entra ID accounts, blocked sign-ins, expired tokens)'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $Devices = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDevices')
        $IosDeviceCount = $Devices.Where({ $_.operatingSystem -in @('iOS', 'iPadOS') }).Count
        $AndroidDeviceCount = $Devices.Where({ $_.operatingSystem -eq 'Android' }).Count
        if ($IosDeviceCount -eq 0 -and $AndroidDeviceCount -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No iOS / iPadOS or Android devices are enrolled in this tenant (or managed devices have not been collected yet).' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneAppProtectionManagedAppPolicies').Where({ $null -ne $_ })
        if ($Policies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'IntuneAppProtectionManagedAppPolicies' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. App protection policies have not been collected yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $PassingActions = @('block', 'wipe')
        $Platforms = foreach ($Definition in @(@('iOS / iPadOS', 'iosManagedAppProtection', $IosDeviceCount), @('Android', 'androidManagedAppProtection', $AndroidDeviceCount))) {
            $OdataType = $Definition[1]
            $PlatformPolicies = $Policies.Where({ $_.URLName -eq $OdataType })
            $QualifyCount = $PlatformPolicies.Where({ $_.appActionIfUnableToAuthenticateUser -in $PassingActions -and $_.isAssigned -eq $true }).Count
            [PSCustomObject]@{
                Label        = $Definition[0]
                OdataType    = $OdataType
                DeviceCount  = $Definition[2]
                Policies     = $PlatformPolicies
                QualifyCount = $QualifyCount
                Pass         = $Definition[2] -eq 0 -or $QualifyCount -gt 0
            }
        }
        $Passed = $Platforms.Where({ -not $_.Pass }).Count -eq 0

        $Summary = if ($Passed) {
            '✅ For every in-scope mobile platform with enrolled devices, an assigned App Protection Policy blocks or wipes managed-app access when the managed app cannot re-authenticate the user (disabled account, blocked sign-in, revoked token).'
        } else {
            '❌ One or more in-scope mobile platforms (iOS / iPadOS, Android) has no assigned App Protection Policy that blocks or wipes managed-app access on authentication failure - disabled accounts and revoked tokens retain a multi-hour window of access to corporate data on personally owned phones.'
        }
        $OverallText = if ($Passed) { 'Pass' } else { 'Fail' }
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n## [App Protection Policies - Unable to Authenticate Action](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsMenu/~/protection)`n`n**Overall: $OverallText**`n")
        foreach ($Platform in $Platforms) {
            $null = $ResultMarkdown.Append("`n### $($Platform.Label) App Protection Policies - Auth Failure Action`n`n")
            if ($Platform.DeviceCount -eq 0) {
                $null = $ResultMarkdown.Append("**Status: Skipped** - No $($Platform.Label) devices enrolled in this tenant.`n")
                continue
            }
            $PlatformText = if ($Platform.Pass) { 'Pass' } else { 'Fail' }
            $null = $ResultMarkdown.Append("**Status: $PlatformText** - $($Platform.DeviceCount) $($Platform.Label) devices enrolled; $($Platform.QualifyCount) of $($Platform.Policies.Count) policies qualify.`n`n| Policy Name | Action on Auth Failure | Assigned | Status |`n| :---------- | :--------------------- | :------- | :----- |`n")
            foreach ($Policy in $Platform.Policies.Where({ $true }, 'First', 10)) {
                $Action = if ([string]::IsNullOrEmpty($Policy.appActionIfUnableToAuthenticateUser)) { 'not configured' } else { $Policy.appActionIfUnableToAuthenticateUser }
                $Assigned = if ($Policy.isAssigned -eq $true) { '✅ Yes' } else { '❌ No' }
                $RowStatus = if ($Policy.appActionIfUnableToAuthenticateUser -in $PassingActions -and $Policy.isAssigned -eq $true) { '✅ Pass' } else { '❌ Fail' }
                $PolicyLink = 'https://intune.microsoft.com/#view/Microsoft_Intune/PolicyInstanceMenuBlade/~/0/policyId/{0}/policyOdataType/%23microsoft.graph.{1}/policyName/{2}' -f $Policy.id, $Platform.OdataType, [Uri]::EscapeDataString([string]$Policy.displayName)
                $null = $ResultMarkdown.Append("| [$($Policy.displayName)]($PolicyLink) | $Action | $Assigned | $RowStatus |`n")
            }
            if ($Platform.Policies.Count -gt 10) {
                $null = $ResultMarkdown.Append("| ... and $($Platform.Policies.Count - 10) more policies | | | |`n")
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
    }
}
