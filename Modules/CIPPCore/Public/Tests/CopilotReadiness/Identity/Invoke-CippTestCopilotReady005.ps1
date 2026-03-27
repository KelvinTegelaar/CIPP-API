function Invoke-CippTestCopilotReady005 {
    <#
    .SYNOPSIS
    Users are actively using Microsoft Teams (Copilot value indicator)
    #>
    param($Tenant)

    # Copilot for Teams provides meeting summaries, chat thread recaps, and real-time assistance.
    # The MS readiness report checks "Uses Teams" — whether users have messaged, called, or
    # attended meetings in the past 30 days. Users with no Teams activity will not benefit
    # from Copilot's Teams features.
    # Threshold: at least 50% of users have any Teams activity in the past 30 days.
    $ActivityThresholdPercent = 50

    try {
        $TeamsData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'TeamsUserActivity'

        if (-not $TeamsData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Teams activity data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Only consider non-deleted users with a UPN
        $Users = @($TeamsData | Where-Object { $_.userPrincipalName -and $_.userPrincipalName -ne '' -and $_.isDeleted -ne $true })

        if ($Users.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No user-level Teams activity data found. This may indicate no licensed Teams users in the tenant.' -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $ActiveUsers = @($Users | Where-Object {
            ([int]($_.teamChatMessageCount ?? 0) +
             [int]($_.privateChatMessageCount ?? 0) +
             [int]($_.callCount ?? 0) +
             [int]($_.meetingCount ?? 0)) -gt 0
        })
        $InactiveUsers = @($Users | Where-Object {
            ([int]($_.teamChatMessageCount ?? 0) +
             [int]($_.privateChatMessageCount ?? 0) +
             [int]($_.callCount ?? 0) +
             [int]($_.meetingCount ?? 0)) -eq 0
        })
        $TotalUsers = $Users.Count
        $ActiveCount = $ActiveUsers.Count
        $ActivityPercent = if ($TotalUsers -gt 0) { [math]::Round(($ActiveCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ActivityPercent -ge $ActivityThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$ActiveCount of $TotalUsers users ($ActivityPercent%)** have Teams activity in the past 30 days — above the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "These users are strong candidates for Copilot in Teams, which provides meeting summaries, chat recaps, and real-time meeting assistance."
        } else {
            $Status = 'Failed'
            $Result = "Only **$ActiveCount of $TotalUsers users ($ActivityPercent%)** have any Teams activity in the past 30 days — below the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "Copilot for Teams delivers the most value to users who regularly use chat, calls, and meetings. "
            $Result += "Consider driving Teams adoption before or alongside a Copilot rollout.`n`n"
            if ($InactiveUsers.Count -gt 0 -and $InactiveUsers.Count -le 20) {
                $Result += "**Inactive users (no Teams activity in 30 days):**`n"
                foreach ($User in $InactiveUsers) {
                    $Result += "- $($User.userPrincipalName)`n"
                }
            } elseif ($InactiveUsers.Count -gt 20) {
                $Result += "**$($InactiveUsers.Count) users** had no Teams activity in the past 30 days."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady005: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady005' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are actively using Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
