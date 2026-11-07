function Invoke-CippTestZTNA41051 {
    <#
    .SYNOPSIS
    Removable storage and device control policies are enforced via Intune
    #>
    param($Tenant)

    $TestId = 'ZTNA41051'
    $Name = 'Removable storage and device control policies are enforced via Intune'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Devices'; Name = $Name; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Endpoint threat protection' }

    try {
        $HasIntune = Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog
        if (-not $HasIntune -or -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset DefenderForEndpoint -RequiredCapabilities 'WINDEFATP', 'MDE_LITE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for both Microsoft Intune and Microsoft Defender for Endpoint.'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $Policies) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Intune configuration policies found in database. Data collection may not yet have completed.'
            return
        }

        $MatchingRoots = '(?i)^(device_vendor_msft_defender_configuration_devicecontrol|device_vendor_msft_policy_config_admx_removablestorage_|device_vendor_msft_policy_config_storage_removable)'
        $InclusiveTargets = @('#microsoft.graph.groupAssignmentTarget', '#microsoft.graph.allDevicesAssignmentTarget', '#microsoft.graph.allLicensedUsersAssignmentTarget')

        $PolicyResults = foreach ($Policy in $Policies) {
            $MatchingCount = @(Get-CippIntuneSettingInstance -Settings $Policy.settings).Where({ [string]$_.settingDefinitionId -match $MatchingRoots }).Count
            if ($MatchingCount -eq 0) { continue }
            $AssignmentCount = @($Policy.assignments).Where({ $_.target.'@odata.type' -in $InclusiveTargets }).Count
            [PSCustomObject]@{
                Name            = $Policy.name
                TemplateFamily  = $Policy.templateReference.templateFamily
                MatchingCount   = $MatchingCount
                AssignmentCount = $AssignmentCount
                LastModified    = $Policy.lastModifiedDateTime
                Status          = if ($AssignmentCount -gt 0) { 'Pass' } else { 'Fail' }
            }
        }
        $PolicyResults = @($PolicyResults)

        if ($PolicyResults.Where({ $_.Status -eq 'Pass' }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ Device control / removable storage access policy is configured and assigned in Microsoft Intune.'
        } elseif ($PolicyResults.Count -eq 0) {
            $Status = 'Investigate'
            $Result = '⚠️ No device control / removable storage policy could be found to evaluate.'
        } else {
            $Status = 'Failed'
            $Result = '❌ A device control / removable storage policy exists but is not assigned to an inclusive target.'
        }

        if ($PolicyResults.Count -gt 0) {
            $Result = @(
                $Result
                ''
                '## [Intune device control and removable storage policies](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/asr)'
                ''
                '| Policy name | Template family | Matching setting count | Assignment count (inclusive targets) | Last modified | Status |'
                '| :---------- | :--------------- | ---------------------: | -----------------------------------: | :------------ | :----- |'
                foreach ($Row in $PolicyResults.Where({ $true }, 'First', 10)) {
                    $StatusDisplay = if ($Row.Status -eq 'Pass') { '✅ Pass' } else { '❌ Fail' }
                    "| $($Row.Name -replace '\|', '\|') | $($Row.TemplateFamily) | $($Row.MatchingCount) | $($Row.AssignmentCount) | $($Row.LastModified) | $StatusDisplay |"
                }
                if ($PolicyResults.Count -gt 10) { "| ... | ... | ... | ... | ... | $($PolicyResults.Count) total policies |" }
            ) -join "`n"
        }

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
