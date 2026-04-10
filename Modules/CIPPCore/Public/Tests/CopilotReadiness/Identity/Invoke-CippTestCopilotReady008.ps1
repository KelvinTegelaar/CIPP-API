function Invoke-CippTestCopilotReady008 {
    <#
    .SYNOPSIS
    Copilot candidate tier breakdown - which users are most ready for Copilot
    #>
    param($Tenant)

    # Score each licensed user across 6 readiness signals from the Copilot readiness report.
    # This is informational — no hard pass/fail — it shows who would benefit most from Copilot.
    # Signal scoring: hasCopilotLicenseAssigned, onQualifiedUpdateChannel, usesTeamsMeetings,
    # usesTeamsChat, usesOutlookEmail, usesOfficeDocs. All booleans, each worth 1 point.
    # High: >=4 signals (power users, best Copilot ROI)
    # Medium: 3 signals (engaged users, good candidates)
    # Low: <=2 signals (low engagement, limited Copilot benefit without adoption work first)

    try {
        $ReadinessData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CopilotReadinessActivity'
        $AllUsers = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        if (-not $ReadinessData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady008' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'Informational' -Name 'Copilot candidate tier breakdown' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
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
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady008' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No licensed active users found in the tenant.' -Risk 'Informational' -Name 'Copilot candidate tier breakdown' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $HighTier = [System.Collections.Generic.List[string]]::new()
        $MediumTier = [System.Collections.Generic.List[string]]::new()
        $LowTier = [System.Collections.Generic.List[string]]::new()

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

            if ($Score -ge 4) {
                $HighTier.Add($User.userPrincipalName)
            } elseif ($Score -ge 3) {
                $MediumTier.Add($User.userPrincipalName)
            } else {
                $LowTier.Add($User.userPrincipalName)
            }
        }

        $Total = $LicensedUsers.Count
        $HighPct = [math]::Round(($HighTier.Count / $Total) * 100, 1)
        $MedPct = [math]::Round(($MediumTier.Count / $Total) * 100, 1)
        $LowPct = [math]::Round(($LowTier.Count / $Total) * 100, 1)

        $Result = "## Copilot Candidate Tier Breakdown`n`n"
        $Result += "Scoring is based on 6 readiness signals from the Microsoft 365 Copilot Readiness report (30-day window).`n`n"
        $Result += "| Tier | Users | % of Tenant | Description |`n"
        $Result += "|------|-------|-------------|-------------|`n"
        $Result += "| **High** (≥4 signals) | $($HighTier.Count) | $HighPct% | Power M365 users — strongest Copilot ROI |`n"
        $Result += "| **Medium** (3 signals) | $($MediumTier.Count) | $MedPct% | Engaged users — good Copilot candidates |`n"
        $Result += "| **Low** (≤2 signals) | $($LowTier.Count) | $LowPct% | Low engagement — adopt M365 basics first |`n"
        $Result += "`n**Signals scored:** Copilot license assigned, qualified update channel, Teams meetings, Teams chat, Outlook email, Office documents (each = 1 point)`n"

        if ($HighTier.Count -gt 0 -and $HighTier.Count -le 20) {
            $Result += "`n**High tier users:**`n"
            foreach ($Upn in $HighTier) { $Result += "- $Upn`n" }
        } elseif ($HighTier.Count -gt 20) {
            $Result += "`n*$($HighTier.Count) users are in the high tier — use the Microsoft 365 Copilot Readiness report in the admin center for the full list.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady008' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Copilot candidate tier breakdown' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady008: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady008' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Copilot candidate tier breakdown' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
