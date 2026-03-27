function Invoke-CippTestCopilotReady005 {
    <#
    .SYNOPSIS
    Users are actively using Microsoft Teams (Copilot value indicator)
    #>
    param($Tenant)

    # Copilot for Teams provides meeting summaries, chat thread recaps, and real-time assistance.
    # The MS readiness report checks usesTeamsMeetings and usesTeamsChat — whether users attended
    # a meeting or participated in chat in the past 30 days. Users not in the readiness report
    # at all have never used any M365 product and are also counted as inactive.
    # Threshold: at least 50% of licensed active users have any Teams activity.
    $ActivityThresholdPercent = 50

    try {
        $ReadinessData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CopilotReadinessActivity'
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        if (-not $ReadinessData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Build lookup of readiness data keyed by UPN
        $ReadinessLookup = @{}
        if ($ReadinessData) {
            foreach ($Entry in ($ReadinessData | Where-Object { $_.userPrincipalName })) {
                $ReadinessLookup[$Entry.userPrincipalName.ToLower()] = $Entry
            }
        }

        # Use licensed active users as the denominator — users absent from the report have never used M365
        $LicensedUsers = @($AllUsers | Where-Object {
                $_.userPrincipalName -and $_.accountEnabled -eq $true -and
                ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' })
            })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No licensed active users found in the tenant.' -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $InactiveUsers = [System.Collections.Generic.List[string]]::new()
        $ActiveCount = 0
        foreach ($User in $LicensedUsers) {
            $Readiness = $ReadinessLookup[$User.userPrincipalName.ToLower()]
            if ($Readiness -and ($Readiness.usesTeamsMeetings -eq $true -or $Readiness.usesTeamsChat -eq $true)) {
                $ActiveCount++
            } else {
                $InactiveUsers.Add($User.userPrincipalName)
            }
        }

        $TotalUsers = $LicensedUsers.Count
        $ActivityPercent = if ($TotalUsers -gt 0) { [math]::Round(($ActiveCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ActivityPercent -ge $ActivityThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$ActiveCount of $TotalUsers licensed users ($ActivityPercent%)** used Teams meetings or chat in the past 30 days — above the $ActivityThresholdPercent% threshold.`n`n"
            $Result += 'These users are strong candidates for Copilot in Teams, which provides meeting summaries, chat recaps, and real-time meeting assistance.'
        } else {
            $Status = 'Failed'
            $Result = "Only **$ActiveCount of $TotalUsers licensed users ($ActivityPercent%)** used Teams meetings or chat in the past 30 days — below the $ActivityThresholdPercent% threshold.`n`n"
            $Result += 'Copilot for Teams delivers the most value to users who regularly use chat and meetings. '
            $Result += "Consider driving Teams adoption before or alongside a Copilot rollout.`n`n"
            if ($InactiveUsers.Count -gt 0 -and $InactiveUsers.Count -le 20) {
                $Result += "**Inactive users (no Teams activity in 30 days):**`n"
                foreach ($Upn in $InactiveUsers) { $Result += "- $Upn`n" }
            } elseif ($InactiveUsers.Count -gt 20) {
                $Result += "**$($InactiveUsers.Count) users** had no Teams meetings or chat activity in the past 30 days."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady005: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
