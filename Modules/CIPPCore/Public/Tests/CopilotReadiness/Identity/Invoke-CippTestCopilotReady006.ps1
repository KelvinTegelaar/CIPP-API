function Invoke-CippTestCopilotReady006 {
    <#
    .SYNOPSIS
    Users are actively using OneDrive/SharePoint for file collaboration (Copilot value indicator)
    #>
    param($Tenant)

    # Copilot adds the most value when users actively store and collaborate on files.
    # The MS readiness report checks usesOfficeDocs \u2014 whether users worked on a document or
    # file in OneDrive or SharePoint in the past 30 days. Users not in the readiness report
    # at all have never used any M365 product and are also counted as inactive.
    # Threshold: at least 50% of licensed active users are using Office docs.
    $ActivityThresholdPercent = 50

    try {
        $ReadinessData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CopilotReadinessActivity'
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        if (-not $ReadinessData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Build lookup of readiness data keyed by UPN
        $ReadinessLookup = @{}
        if ($ReadinessData) {
            foreach ($Entry in ($ReadinessData | Where-Object { $_.userPrincipalName })) {
                $ReadinessLookup[$Entry.userPrincipalName.ToLower()] = $Entry
            }
        }

        # Use licensed active users as the denominator \u2014 users absent from the report have never used M365
        $LicensedUsers = @($AllUsers | Where-Object {
                $_.userPrincipalName -and $_.accountEnabled -eq $true -and
                ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' })
            })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No licensed active users found in the tenant.' -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $InactiveUsers = [System.Collections.Generic.List[string]]::new()
        $ActiveCount = 0
        foreach ($User in $LicensedUsers) {
            $Readiness = $ReadinessLookup[$User.userPrincipalName.ToLower()]
            if ($Readiness -and $Readiness.usesOfficeDocs -eq $true) {
                $ActiveCount++
            } else {
                $InactiveUsers.Add($User.userPrincipalName)
            }
        }

        $TotalUsers = $LicensedUsers.Count
        $ActivityPercent = if ($TotalUsers -gt 0) { [math]::Round(($ActiveCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ActivityPercent -ge $ActivityThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$ActiveCount of $TotalUsers licensed users ($ActivityPercent%)** worked on OneDrive or SharePoint files in the past 30 days \u2014 above the $ActivityThresholdPercent% threshold.`n`n"
            $Result += 'These users are strong candidates for Copilot, which provides the most value when users actively collaborate on files in Microsoft 365.'
        } else {
            $Status = 'Failed'
            $Result = "Only **$ActiveCount of $TotalUsers licensed users ($ActivityPercent%)** worked on OneDrive or SharePoint files in the past 30 days \u2014 below the $ActivityThresholdPercent% threshold.`n`n"
            $Result += 'Copilot delivers the most value when users regularly store and collaborate on files in OneDrive and SharePoint. '
            $Result += "Consider driving file collaboration adoption before or alongside a Copilot rollout.`n`n"
            if ($InactiveUsers.Count -gt 0 -and $InactiveUsers.Count -le 20) {
                $Result += "**Inactive users (no Office doc activity in 30 days):**`n"
                foreach ($Upn in $InactiveUsers) { $Result += "- $Upn`n" }
            } elseif ($InactiveUsers.Count -gt 20) {
                $Result += "**$($InactiveUsers.Count) users** had no OneDrive or SharePoint file activity in the past 30 days."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady006: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady006' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are actively using OneDrive/SharePoint' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
