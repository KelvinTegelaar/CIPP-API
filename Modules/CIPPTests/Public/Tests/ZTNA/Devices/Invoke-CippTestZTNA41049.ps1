function Invoke-CippTestZTNA41049 {
    <#
    .SYNOPSIS
    The Microsoft Defender Antivirus user interface is hidden from end users
    #>
    param($Tenant)

    $TestId = 'ZTNA41049'
    $Name = 'The Microsoft Defender Antivirus user interface is hidden from end users'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'Low'; Category = 'Endpoint threat protection' }

    try {
        $HasIntune = Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog
        if (-not $HasIntune -or -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for both Microsoft Intune and Microsoft Defender for Endpoint.'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        $DeviceConfigurations = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneDeviceConfigurations'
        if (-not $Policies -and -not $DeviceConfigurations) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Intune configuration policies found in database. Data collection may not yet have completed.'
            return
        }

        $ControlNames = @{
            disablevirusui                             = 'Virus/AV UI'
            disableaccountprotectionui                 = 'Account UI'
            disableappbrowserui                        = 'App/browser UI'
            disabledevicesecurityui                    = 'Device security UI'
            disablefamilyui                            = 'Family UI'
            disablehealthui                            = 'Health UI'
            disablenetworkui                           = 'Network UI'
            disablecleartpmbutton                      = 'Clear TPM button'
            disabletpmfirmwareupdatewarning            = 'TPM firmware warning'
            hideransomwaredatarecovery                 = 'Ransomware recovery UI'
            hidesecureboot                             = 'Secure Boot UI'
            hidetpmtroubleshooting                     = 'TPM troubleshooting UI'
            hidewindowssecuritynotificationareacontrol = 'Notification-area icon'
            disableenhancednotifications               = 'Noncritical notifications'
            disablenotifications                       = 'All notifications'
        }
        $ControlPattern = '(?i)_({0})$' -f ($ControlNames.Keys -join '|')

        $PrimaryResults = [System.Collections.Generic.List[object]]::new()
        $ContextResults = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in @($Policies).Where({ $_.technologies -match '(?i)\bmdm\b' })) {
            $AssignmentCount = [int]$Policy.assignments.Count
            foreach ($Instance in @(Get-CippIntuneSettingInstance -Settings $Policy.settings)) {
                if ([string]$Instance.settingDefinitionId -notmatch $ControlPattern) { continue }
                $Control = $Matches[1].ToLowerInvariant()
                $Value = [string]$Instance.choiceSettingValue.value
                $State = if ($Value -match '(?i)_1$') { 'Hidden' } elseif ($Value -match '(?i)_0$') { 'Visible' } else { 'N/A' }
                $Row = [PSCustomObject]@{
                    PolicyName      = $Policy.name
                    Source          = 'Settings Catalog'
                    AssignmentCount = $AssignmentCount
                    Control         = $ControlNames[$Control]
                    Raw             = $Instance.settingDefinitionId
                    State           = $State
                    Status          = if ($State -eq 'N/A') { 'Investigate' } elseif ($State -eq 'Hidden' -and $AssignmentCount -gt 0) { 'Pass' } else { 'Fail' }
                }
                if ($Control -eq 'disablevirusui') { $PrimaryResults.Add($Row) } else { $ContextResults.Add($Row) }
            }
        }

        if ($PrimaryResults.Count -eq 0) {
            $LegacyControls = @(
                @{ Name = 'Virus/AV UI'; Property = 'defenderSecurityCenterDisableVirusUI'; IsPrimary = $true }
                @{ Name = 'Account UI'; Property = 'defenderSecurityCenterDisableAccountUI' }
                @{ Name = 'App/browser UI'; Property = 'defenderSecurityCenterDisableAppBrowserUI' }
                @{ Name = 'Device security UI'; Property = 'defenderSecurityCenterDisableHardwareUI' }
                @{ Name = 'Family UI'; Property = 'defenderSecurityCenterDisableFamilyUI' }
                @{ Name = 'Health UI'; Property = 'defenderSecurityCenterDisableHealthUI' }
                @{ Name = 'Network UI'; Property = 'defenderSecurityCenterDisableNetworkUI' }
                @{ Name = 'Clear TPM button'; Property = 'defenderSecurityCenterDisableClearTpmUI' }
                @{ Name = 'TPM firmware warning'; Property = 'defenderSecurityCenterDisableVulnerableTpmFirmwareUpdateUI' }
                @{ Name = 'Ransomware recovery UI'; Property = 'defenderSecurityCenterDisableRansomwareUI' }
                @{ Name = 'Secure Boot UI'; Property = 'defenderSecurityCenterDisableSecureBootUI' }
                @{ Name = 'TPM troubleshooting UI'; Property = 'defenderSecurityCenterDisableTroubleshootingUI' }
                @{ Name = 'Notification-area icon'; Property = 'defenderSecurityCenterDisableNotificationAreaUI' }
                @{ Name = 'Noncritical notifications'; Property = 'defenderSecurityCenterNotificationsFromApp'; ExpectedValue = 'blockNoncriticalNotifications' }
                @{ Name = 'All notifications'; Property = 'defenderSecurityCenterNotificationsFromApp'; ExpectedValue = 'blockAllNotifications' }
            )
            foreach ($Configuration in @($DeviceConfigurations).Where({ $_.'@odata.type' -eq '#microsoft.graph.windows10EndpointProtectionConfiguration' })) {
                $AssignmentCount = [int]$Configuration.assignments.Count
                foreach ($Control in $LegacyControls) {
                    $Value = $Configuration.($Control.Property)
                    if ($null -eq $Value) { continue }
                    $State = if ($Value -is [bool]) {
                        if ($Value) { 'Hidden' } else { 'Visible' }
                    } elseif ($Control.ExpectedValue) {
                        # blockAllNotifications suppresses noncritical notifications too
                        if ($Value -eq $Control.ExpectedValue -or $Value -eq 'blockAllNotifications') { 'Hidden' } elseif ($Value -eq 'blockNoncriticalNotifications') { 'Visible' } else { 'N/A' }
                    } else { 'N/A' }
                    $Row = [PSCustomObject]@{
                        PolicyName      = $Configuration.displayName
                        Source          = 'Legacy EPP'
                        AssignmentCount = $AssignmentCount
                        Control         = $Control.Name
                        Raw             = $Control.Property
                        State           = $State
                        Status          = if ($State -eq 'N/A') { 'Investigate' } elseif ($State -eq 'Hidden' -and $AssignmentCount -gt 0) { 'Pass' } else { 'Fail' }
                    }
                    if ($Control.IsPrimary) { $PrimaryResults.Add($Row) } else { $ContextResults.Add($Row) }
                }
            }
        }

        if ($PrimaryResults.Count -eq 0) {
            $Status = 'Investigate'
            $Result = '⚠️ The `DisableVirusUI` state could not be determined on either the Settings Catalog or legacy endpoint protection surface; verify configuration in the Intune portal.'
        } elseif ($PrimaryResults.Where({ $_.Status -eq 'Fail' }).Count -gt 0) {
            $Status = 'Failed'
            $Result = '❌ The Defender Antivirus UI is not hidden — `DisableVirusUI` is disabled, or enabled only in an unassigned policy.'
        } elseif ($PrimaryResults.Where({ $_.Status -eq 'Investigate' }).Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ Could not determine `DisableVirusUI` state: the configured value could not be interpreted.'
        } else {
            $Status = 'Passed'
            $Result = '✅ The Microsoft Defender Antivirus (Virus & threat protection) UI is hidden from end users — an assigned policy enables `DisableVirusUI`.'
        }

        $AllResults = @($PrimaryResults; $ContextResults)
        if ($AllResults.Count -gt 0) {
            $StatusDisplay = @{ Pass = '✅ Pass'; Fail = '❌ Fail'; Investigate = '⚠️ Investigate' }
            $Result = @(
                $Result
                ''
                '## [Intune configuration policies](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/DevicesMenu/~/configuration)'
                ''
                '| Policy/Profile | Source | Assignment Count | Canonical control | Raw setting/property | Normalized state | Status |'
                '| :--- | :--- | ---: | :--- | :--- | :--- | :--- |'
                foreach ($Row in $AllResults.Where({ $true }, 'First', 10)) {
                    "| $($Row.PolicyName -replace '\|', '\|') | $($Row.Source) | $($Row.AssignmentCount) | $($Row.Control) | $($Row.Raw) | $($Row.State) | $($StatusDisplay[$Row.Status]) |"
                }
                if ($AllResults.Count -gt 10) { "| ... | | | | | | $($AllResults.Count) total configurations |" }
            ) -join "`n"
        }

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
