function Invoke-CippTestZTNA51001 {
    <#
    .SYNOPSIS
    Windows Endpoint Privilege Management is configured and assigned
    #>
    param($Tenant)

    $TestId = 'ZTNA51001'
    $Name = 'Windows Endpoint Privilege Management is configured and assigned'

    try {
        # Upstream grades a missing Intune Suite / EPM licence as a failure, not as not-applicable
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -RequiredCapabilities @('Intune-EPM') -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown '❌ Windows endpoints are not protected by centrally governed elevation control — the tenant does not have an active Intune Suite license (no Intune-EPM service plan). EPM is an Intune Suite add-on and cannot be enabled without the license.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $ConfigurationPolicies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies').Where({ $null -ne $_ })
        if ($ConfigurationPolicies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies' -CountsOnly)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. Intune configuration policies have not been collected yet.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
            return
        }

        $EpmPolicies = $ConfigurationPolicies.Where({ $_.templateReference.templateFamily -eq 'endpointSecurityEndpointPrivilegeManagement' })
        $SettingsPolicies = $EpmPolicies.Where({ $_.templateReference.templateDisplayName -match 'Elevation settings' })
        $RulesPolicies = $EpmPolicies.Where({ $_.templateReference.templateDisplayName -notmatch 'Elevation settings' -and $_.templateReference.templateDisplayName -match 'Elevation rules' })
        $SettingsAssigned = $SettingsPolicies.Where({ @($_.assignments).Count -gt 0 }).Count -gt 0
        $RulesAssigned = $RulesPolicies.Where({ @($_.assignments).Count -gt 0 }).Count -gt 0

        if ($SettingsAssigned -and $RulesAssigned) {
            $Status = 'Passed'
            $Summary = '✅ At least one Windows Endpoint Privilege Management elevation settings policy is assigned, and at least one EPM elevation rules policy is created and assigned.'
        } elseif ($SettingsAssigned -or $RulesAssigned) {
            $Status = 'Failed'
            $Present = if ($SettingsAssigned) { 'elevation settings' } else { 'elevation rules' }
            $Missing = if ($SettingsAssigned) { 'elevation rules' } else { 'elevation settings' }
            $Summary = "❌ Windows endpoints are not protected by centrally governed elevation control — an EPM $Present policy is assigned but no $Missing policy is assigned. Both policy types are required."
        } else {
            $Status = 'Failed'
            $Summary = '❌ Windows endpoints are not protected by centrally governed elevation control — no elevation settings policy or elevation rules policy is configured and assigned.'
        }

        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n")
        if ($EpmPolicies.Count -gt 0) {
            $null = $ResultMarkdown.Append("## [Windows Endpoint Privilege Management policies](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/epm)`n`nTotal EPM policies found: **$($EpmPolicies.Count)**`n`n| Policy Name | Policy Type | Assigned | Status |`n| :---------- | :---------- | :------- | :----- |`n")
            foreach ($Policy in $EpmPolicies.Where({ $true }, 'First', 10)) {
                $PolicyType = if ($Policy.templateReference.templateDisplayName -match 'Elevation settings') { 'Elevation Settings' } elseif ($Policy.templateReference.templateDisplayName -match 'Elevation rules') { 'Elevation Rules' } else { 'Other' }
                $Assigned = if (@($Policy.assignments).Count -gt 0) { '✅ Yes' } else { '❌ No' }
                $RowStatus = if (@($Policy.assignments).Count -gt 0) { 'Pass' } else { 'Fail' }
                $null = $ResultMarkdown.Append("| $($Policy.name) | $PolicyType | $Assigned | $RowStatus |`n")
            }
            if ($EpmPolicies.Count -gt 10) {
                $null = $ResultMarkdown.Append("| ... | ... | ... | ... |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Devices'
    }
}
