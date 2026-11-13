function Invoke-CippTestZTNA51018 {
    <#
    .SYNOPSIS
    Windows App Control for Business (WDAC) is configured and assigned via Intune
    #>
    param($Tenant)

    $TestId = 'ZTNA51018'
    $Name = 'Windows App Control for Business (WDAC) is configured and assigned via Intune'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $WindowsDeviceCount = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDevices').Where({ $_.operatingSystem -eq 'Windows' }).Count
        if ($WindowsDeviceCount -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Windows devices are enrolled in this tenant (or managed devices have not been collected yet).' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $ConfigurationPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies').Where({ $null -ne $_ })
        if ($ConfigurationPolicies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. Intune configuration policies have not been collected yet.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }
        $AppControlPolicies = $ConfigurationPolicies.Where({ $_.templateReference.templateFamily -eq 'endpointSecurityApplicationControl' })
        $WindowsPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($Policy in $AppControlPolicies) {
            if ($Policy.platforms -notmatch 'windows10') { continue }
            $BuildOption = 'Not configured'
            foreach ($Setting in @($Policy.settings)) {
                $ChoiceValue = [string]$Setting.settingInstance.choiceSettingValue.value
                if ($Setting.settingInstance.settingDefinitionId -match 'device_vendor_msft_policy_config_applicationcontrol' -and $ChoiceValue) {
                    if ($ChoiceValue -match '_built_in_controls_selected$') { $BuildOption = 'Built-in controls'; break }
                    if ($ChoiceValue -match '_configure_xml_selected$') { $BuildOption = 'Configure XML'; break }
                    if ($ChoiceValue -match '_upload_xml_selected$') { $BuildOption = 'Upload XML'; break }
                }
            }
            $IsAssigned = @($Policy.assignments).Count -gt 0
            $WindowsPolicies.Add([PSCustomObject]@{
                    Name        = $Policy.name
                    BuildOption = $BuildOption
                    IsAssigned  = $IsAssigned
                    Qualifies   = $IsAssigned -and $BuildOption -ne 'Not configured'
                })
        }

        $QualifyingCount = $WindowsPolicies.Where({ $_.Qualifies }).Count
        $Passed = $QualifyingCount -gt 0

        $Summary = if ($Passed) {
            '✅ Windows App Control for Business is configured (either via Microsoft built-in controls or a custom WDAC XML policy) and assigned to managed Windows devices via at least one Intune Settings Catalog policy.'
        } else {
            "❌ Windows devices are enrolled but no Intune App Control for Business policy is configured AND assigned — managed Windows devices have no kernel-level allow-listing of executables, allowing unsigned and unknown binaries to run with the user's token before any detective control fires."
        }
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n## [Windows App Control for Business — Settings Catalog policy posture](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/appControl)`n`n")
        if ($WindowsPolicies.Count -gt 0) {
            $VerdictText = if ($Passed) { 'Pass' } else { 'Fail' }
            $null = $ResultMarkdown.Append("**Status: $VerdictText** — $QualifyingCount of $($WindowsPolicies.Count) App Control policies are assigned with a configured build option.`n`n| Policy name | Build option | Assigned | Status |`n| :---------- | :----------- | :------- | :----- |`n")
            foreach ($Policy in $WindowsPolicies.Where({ $true }, 'First', 10)) {
                $Assigned = if ($Policy.IsAssigned) { '✅ Yes' } else { '❌ No' }
                $RowStatus = if ($Policy.Qualifies) { '✅ Pass' } else { '❌ Fail' }
                $null = $ResultMarkdown.Append("| $($Policy.Name) | $($Policy.BuildOption) | $Assigned | $RowStatus |`n")
            }
            if ($WindowsPolicies.Count -gt 10) {
                $null = $ResultMarkdown.Append("| ... ($($WindowsPolicies.Count) total) | | | |`n")
            }
        } else {
            $null = $ResultMarkdown.Append("**Status: Fail** — No App Control policies target the Windows platform.`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    }
}
