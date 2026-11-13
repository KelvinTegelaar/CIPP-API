function Invoke-CippTestZTNA51014 {
    <#
    .SYNOPSIS
    App Protection Policies block managed-app access on jailbroken or rooted mobile devices
    #>
    param($Tenant)

    $TestId = 'ZTNA51014'
    $Name = 'App Protection Policies block managed-app access on jailbroken or rooted mobile devices'

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

        $AcceptableActions = @('block', 'wipe')
        $AcceptableAttestationTypes = @('basicIntegrity', 'basicIntegrityAndDeviceCertification')
        $IosRows = foreach ($Policy in $Policies.Where({ $_.URLName -eq 'iosManagedAppProtection' })) {
            [PSCustomObject]@{
                Policy  = $Policy
                Setting = if ($Policy.deviceComplianceRequired -eq $true) { '✅ True' } else { '❌ False' }
                Action  = $Policy.appActionIfDeviceComplianceRequired
                Pass    = $Policy.deviceComplianceRequired -eq $true -and $Policy.appActionIfDeviceComplianceRequired -in $AcceptableActions -and $Policy.isAssigned -eq $true
            }
        }
        $AndroidRows = foreach ($Policy in $Policies.Where({ $_.URLName -eq 'androidManagedAppProtection' })) {
            $Attestation = $Policy.requiredAndroidSafetyNetDeviceAttestationType
            [PSCustomObject]@{
                Policy  = $Policy
                Setting = if ($Attestation -in $AcceptableAttestationTypes) { "✅ $Attestation" } else { "❌ $Attestation" }
                Action  = $Policy.appActionIfAndroidSafetyNetDeviceAttestationFailed
                Pass    = $Attestation -in $AcceptableAttestationTypes -and $Policy.appActionIfAndroidSafetyNetDeviceAttestationFailed -in $AcceptableActions -and $Policy.isAssigned -eq $true
            }
        }

        $Platforms = @(
            [PSCustomObject]@{ Label = 'iOS / iPadOS'; Title = 'Jailbreak Gate'; OdataType = 'iosManagedAppProtection'; DeviceCount = $IosDeviceCount; Rows = @($IosRows); SettingHeader = 'Device compliance required'; ActionHeader = 'Action on Non-Compliance' }
            [PSCustomObject]@{ Label = 'Android'; Title = 'Root Gate'; OdataType = 'androidManagedAppProtection'; DeviceCount = $AndroidDeviceCount; Rows = @($AndroidRows); SettingHeader = 'Attestation type requested'; ActionHeader = 'Action on attestation failure' }
        )
        $Passed = $Platforms.Where({ $_.DeviceCount -gt 0 -and $_.Rows.Where({ $_.Pass }).Count -eq 0 }).Count -eq 0

        $Summary = if ($Passed) {
            '✅ For every in-scope mobile platform with enrolled devices, an assigned App Protection Policy blocks or wipes managed-app access on jailbroken / rooted devices.'
        } else {
            '❌ One or more in-scope mobile platforms (iOS / iPadOS, Android) has no assigned App Protection Policy that blocks or wipes managed-app access on jailbroken / rooted devices — the MAM data-protection model can be silently bypassed by users on compromised personal devices.'
        }
        $OverallText = if ($Passed) { 'Pass' } else { 'Fail' }
        $PortalLink = 'https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsMenu/~/protection'
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n**Overall: $OverallText**`n")
        foreach ($Platform in $Platforms) {
            $null = $ResultMarkdown.Append("`n### [$($Platform.Label) App Protection Policies — $($Platform.Title)]($PortalLink)`n`n")
            if ($Platform.DeviceCount -eq 0) {
                $null = $ResultMarkdown.Append("**Status: Skipped** — No $($Platform.Label) devices enrolled in this tenant.`n")
                continue
            }
            $QualifyCount = $Platform.Rows.Where({ $_.Pass }).Count
            $PlatformText = if ($QualifyCount -gt 0) { 'Pass' } else { 'Fail' }
            $null = $ResultMarkdown.Append("**Status: $PlatformText** — $($Platform.DeviceCount) $($Platform.Label) device(s) enrolled; $QualifyCount of $($Platform.Rows.Count) policies qualify.`n`n")
            if ($Platform.Rows.Count -eq 0) {
                $null = $ResultMarkdown.Append("No App Protection Policies found for $($Platform.Label).`n")
                continue
            }
            $null = $ResultMarkdown.Append("| Policy name | $($Platform.SettingHeader) | $($Platform.ActionHeader) | Assigned | Status |`n| :---------- | :------------------------- | :----------------------- | :------- | :----- |`n")
            $OrderedRows = @($Platform.Rows.Where({ $_.Pass })) + @($Platform.Rows.Where({ -not $_.Pass }))
            foreach ($Row in $OrderedRows.Where({ $true }, 'First', 10)) {
                $Action = if ($Row.Action -in $AcceptableActions) { "✅ $($Row.Action)" } else { "❌ $($Row.Action)" }
                $Assigned = if ($Row.Policy.isAssigned -eq $true) { '✅ Yes' } else { '❌ No' }
                $RowStatus = if ($Row.Pass) { '✅ Pass' } else { '❌ Fail' }
                $PolicyLink = 'https://intune.microsoft.com/#view/Microsoft_Intune/PolicyInstanceMenuBlade/~/0/policyId/{0}/policyOdataType/%23microsoft.graph.{1}/policyName/{2}' -f $Row.Policy.id, $Platform.OdataType, [Uri]::EscapeDataString([string]$Row.Policy.displayName)
                $null = $ResultMarkdown.Append("| [$($Row.Policy.displayName)]($PolicyLink) | $($Row.Setting) | $Action | $Assigned | $RowStatus |`n")
            }
            if ($Platform.Rows.Count -gt 10) {
                $null = $ResultMarkdown.Append("| ... | | | | _$($Platform.Rows.Count) total_ |`n")
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
