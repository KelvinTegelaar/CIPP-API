function Invoke-CippTestZTNA41080 {
    <#
    .SYNOPSIS
    Conditional Access App Control session policies are enforced for sensitive cloud apps
    #>
    param($Tenant)

    $TestId = 'ZTNA41080'
    $Name = 'Conditional Access App Control session policies are enforced for sensitive cloud apps'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Identity'; Name = $Name; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Identity threat protection' }

    try {
        $HasEntra = Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog
        if (-not $HasEntra -or -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -RequiredCapabilities 'ADALLOM_S_STANDALONE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for both Microsoft Entra ID P1 and Microsoft Defender for Cloud Apps. Required capabilities: AAD_PREMIUM, ADALLOM_S_STANDALONE.'
            return
        }

        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CAPolicies) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Conditional Access policies found in database. Data collection may not yet have completed.'
            return
        }

        $KnownTargets = @{ All = 'All cloud apps'; Office365 = 'Office 365'; MicrosoftAdminPortals = 'Microsoft admin portals' }
        $MatchingPolicies = foreach ($Policy in $CAPolicies.Where({ $_.state -eq 'enabled' })) {
            $SessionControl = $Policy.sessionControls.cloudAppSecurity
            $TargetApps = @($Policy.conditions.applications.includeApplications).Where({ -not [string]::IsNullOrWhiteSpace($_) })
            if ($SessionControl.isEnabled -ne $true -or $TargetApps.Count -eq 0) { continue }

            $SelectedCount = $TargetApps.Where({ -not $KnownTargets.ContainsKey($_) }).Count
            $TargetLabels = @(
                foreach ($App in $TargetApps) { if ($KnownTargets.ContainsKey($App)) { $KnownTargets[$App] } }
                if ($SelectedCount -eq 1) { '1 selected app' } elseif ($SelectedCount -gt 1) { "$SelectedCount selected apps" }
            )
            $SecurityType = if ($SessionControl.cloudAppSecurityType) { $SessionControl.cloudAppSecurityType } else { 'Not configured' }
            [PSCustomObject]@{
                DisplayName  = $Policy.displayName
                Id           = $Policy.id
                State        = $Policy.state
                TargetApps   = $TargetLabels -join ', '
                SecurityType = $SecurityType
                Status       = if ($SecurityType -eq 'unknownFutureValue') { 'Investigate' } else { 'Pass' }
            }
        }
        $MatchingPolicies = @($MatchingPolicies)

        if ($MatchingPolicies.Where({ $_.Status -eq 'Pass' }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ At least one enabled Conditional Access policy enforces Microsoft Defender for Cloud Apps session control via Conditional Access App Control.'
        } elseif ($MatchingPolicies.Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ Conditional Access App Control is enabled, but every matching policy returned an unknown Cloud App Security type. Review the policies in Microsoft Entra.'
        } else {
            $Status = 'Failed'
            $Result = '❌ No enabled Conditional Access policy has Defender for Cloud Apps session control enabled for a cloud app.'
        }

        $PortalUrl = 'https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade'
        $Result = @(
            $Result
            ''
            "## [Microsoft Entra > Conditional Access > Policies]($PortalUrl)"
            ''
            '| Policy display name | State | Target apps | Cloud App Security type | Is enabled | Status |'
            '| :------------------ | :---- | :---------- | :---------------------- | :--------- | :----- |'
            if ($MatchingPolicies.Count -eq 0) { '| No matching policies found | — | — | — | — | ❌ Fail |' }
            foreach ($Row in $MatchingPolicies.Where({ $true }, 'First', 10)) {
                $StatusDisplay = if ($Row.Status -eq 'Pass') { '✅ Pass' } else { '⚠️ Investigate' }
                "| [$($Row.DisplayName -replace '\|', '\|')](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Row.Id)) | $($Row.State) | $($Row.TargetApps) | $($Row.SecurityType) | True | $StatusDisplay |"
            }
            if ($MatchingPolicies.Count -gt 10) { "`n... and $($MatchingPolicies.Count - 10) more. [Microsoft Entra > Conditional Access > Policies]($PortalUrl)" }
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
