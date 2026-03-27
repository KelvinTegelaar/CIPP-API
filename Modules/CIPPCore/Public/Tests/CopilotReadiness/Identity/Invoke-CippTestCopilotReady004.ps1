function Invoke-CippTestCopilotReady004 {
    <#
    .SYNOPSIS
    Users are actively using Exchange Online email (Copilot value indicator)
    #>
    param($Tenant)

    # Copilot for Outlook adds AI-assisted email drafting, summarization, and coaching.
    # The MS readiness report checks "Uses Email" — whether users have sent or received email
    # in the past 30 days. Inactive email users are unlikely to benefit from Copilot in Outlook.
    # Threshold: at least 50% of licensed users have sent or received email in the past 30 days.
    $ActivityThresholdPercent = 50

    try {
        $EmailData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'EmailActivity'

        if (-not $EmailData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady004' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No email activity data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'Users are actively using Exchange Online email' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Only consider non-deleted users with a UPN
        $Users = @($EmailData | Where-Object { $_.userPrincipalName -and $_.userPrincipalName -ne '' -and $_.isDeleted -ne $true })

        if ($Users.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady004' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No user-level email activity data found. This may indicate no licensed Exchange Online users in the tenant.' -Risk 'Medium' -Name 'Users are actively using Exchange Online email' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $ActiveUsers = @($Users | Where-Object { ([int]($_.sendCount ?? 0) + [int]($_.receiveCount ?? 0)) -gt 0 })
        $InactiveUsers = @($Users | Where-Object { ([int]($_.sendCount ?? 0) + [int]($_.receiveCount ?? 0)) -eq 0 })
        $TotalUsers = $Users.Count
        $ActiveCount = $ActiveUsers.Count
        $ActivityPercent = if ($TotalUsers -gt 0) { [math]::Round(($ActiveCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ActivityPercent -ge $ActivityThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$ActiveCount of $TotalUsers users ($ActivityPercent%)** sent or received email in the past 30 days — above the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "These users are good candidates for Copilot in Outlook, which provides AI-assisted drafting, summarization, and email coaching."
        } else {
            $Status = 'Failed'
            $Result = "Only **$ActiveCount of $TotalUsers users ($ActivityPercent%)** sent or received email in the past 30 days — below the $ActivityThresholdPercent% threshold.`n`n"
            $Result += "Copilot for Outlook delivers the most value to active email users. "
            $Result += "Consider reviewing Exchange Online license assignment and adoption before rolling out Copilot.`n`n"
            if ($InactiveUsers.Count -gt 0 -and $InactiveUsers.Count -le 20) {
                $Result += "**Inactive users (no email activity in 30 days):**`n"
                foreach ($User in $InactiveUsers) {
                    $Result += "- $($User.displayName) ($($User.userPrincipalName))`n"
                }
            } elseif ($InactiveUsers.Count -gt 20) {
                $Result += "**$($InactiveUsers.Count) users** had no email activity in the past 30 days."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady004' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are actively using Exchange Online email' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady004: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady004' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are actively using Exchange Online email' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
