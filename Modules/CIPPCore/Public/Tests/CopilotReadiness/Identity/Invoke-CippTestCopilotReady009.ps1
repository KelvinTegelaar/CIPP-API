function Invoke-CippTestCopilotReady009 {
    <#
    .SYNOPSIS
    Majority of licensed users are Medium or High Copilot candidates (adoption readiness)
    #>
    param($Tenant)

    # Using the same 6-signal scoring as test 008. Pass if at least 70% of licensed users
    # score Medium (3 signals) or above — indicating the tenant has broad enough M365 engagement
    # to make a Copilot rollout worthwhile without first needing a major adoption campaign.
    $AdoptionThresholdPercent = 70

    try {
        $ReadinessData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CopilotReadinessActivity'
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        if (-not $ReadinessData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady009' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Majority of users are Copilot-ready (Medium or above)' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $ReadinessLookup = @{}
        if ($ReadinessData) {
            foreach ($Entry in ($ReadinessData | Where-Object { $_.userPrincipalName })) {
                $ReadinessLookup[$Entry.userPrincipalName.ToLower()] = $Entry
            }
        }

        $LicensedUsers = @($AllUsers | Where-Object {
                $_.userPrincipalName -and $_.accountEnabled -eq $true -and
                ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' })
            })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady009' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No licensed active users found in the tenant.' -Risk 'High' -Name 'Majority of users are Copilot-ready (Medium or above)' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $MediumOrAbove = 0
        $LowCount = 0
        foreach ($User in $LicensedUsers) {
            $R = $ReadinessLookup[$User.userPrincipalName.ToLower()]
            $Score = 0
            if ($R) {
                if ($R.hasCopilotLicenseAssigned -eq $true) { $Score++ }
                if ($R.onQualifiedUpdateChannel -eq $true) { $Score++ }
                if ($R.usesTeamsMeetings -eq $true) { $Score++ }
                if ($R.usesTeamsChat -eq $true) { $Score++ }
                if ($R.usesOutlookEmail -eq $true) { $Score++ }
                if ($R.usesOfficeDocs -eq $true) { $Score++ }
            }
            if ($Score -ge 3) { $MediumOrAbove++ } else { $LowCount++ }
        }

        $Total = $LicensedUsers.Count
        $ReadyPercent = [math]::Round(($MediumOrAbove / $Total) * 100, 1)

        if ($ReadyPercent -ge $AdoptionThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$MediumOrAbove of $Total licensed users ($ReadyPercent%)** score Medium or above on Copilot readiness signals — above the $AdoptionThresholdPercent% threshold.`n`n"
            $Result += 'This tenant has strong M365 engagement across the user base and is well-positioned for a Copilot rollout.'
        } else {
            $Status = 'Failed'
            $Result = "Only **$MediumOrAbove of $Total licensed users ($ReadyPercent%)** score Medium or above on Copilot readiness signals — below the $AdoptionThresholdPercent% threshold.`n`n"
            $Result += "**$LowCount users** have low M365 engagement (≤2 of 6 signals). Copilot delivers the most value where users are already active across Teams, Outlook, and Office apps.`n`n"
            $Result += "Consider running an M365 adoption campaign — focused on Teams meetings, Teams chat, Outlook, and OneDrive/SharePoint file usage — before or alongside a Copilot rollout.`n`n"
            $Result += 'See test CopilotReady008 for a full breakdown of users by tier.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady009' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Majority of users are Copilot-ready (Medium or above)' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady009: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady009' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Majority of users are Copilot-ready (Medium or above)' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
