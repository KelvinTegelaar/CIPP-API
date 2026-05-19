function Invoke-CippTestCopilotReady007 {
    <#
    .SYNOPSIS
    Users are on a qualified Microsoft 365 Apps update channel (Copilot prerequisite)
    #>
    param($Tenant)

    # Copilot features in Word, Excel, PowerPoint, Outlook, and OneNote require the M365 desktop
    # client to be on Current Channel or Monthly Enterprise Channel — the two "qualified" update
    # channels that receive Copilot feature updates. Users on Semi-Annual Enterprise Channel or
    # other slower channels will not receive Copilot features even with a valid license.
    # Users not in the readiness report at all have never used any M365 product and are counted
    # as not on a qualified channel.
    # Threshold: at least 70% of licensed active users are on a qualified update channel. Risk: High.
    $ChannelThresholdPercent = 70

    try {
        $ReadinessData = Get-CIPPTestData -TenantFilter $Tenant -Type 'CopilotReadinessActivity'
        $AllUsers = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $ReadinessData -and -not $AllUsers) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady007' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot readiness activity or user data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Users are on a qualified M365 Apps update channel' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # Build lookup of readiness data keyed by UPN
        $ReadinessLookup = @{}
        if ($ReadinessData) {
            foreach ($Entry in ($ReadinessData | Where-Object { $_.userPrincipalName })) {
                $ReadinessLookup[$Entry.userPrincipalName.ToLower()] = $Entry
            }
        }

        # Filter to users with an active M365 Apps (desktop) license plan — update channel only
        # applies to users with a license that includes M365 Apps for desktop.
        $LicensedUsers = @($AllUsers | Where-Object {
            $_.userPrincipalName -and $_.accountEnabled -eq $true -and
            ($_.assignedPlans | Where-Object { $_.service -eq 'MicrosoftOffice' -and $_.capabilityStatus -eq 'Enabled' })
        })

        if ($LicensedUsers.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady007' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No users with an active M365 Apps license were found. Update channel check is not applicable.' -Risk 'High' -Name 'Users are on a qualified M365 Apps update channel' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $NotQualifiedUsers = [System.Collections.Generic.List[string]]::new()
        $QualifiedCount = 0
        foreach ($User in $LicensedUsers) {
            $Readiness = $ReadinessLookup[$User.userPrincipalName.ToLower()]
            if ($Readiness -and $Readiness.onQualifiedUpdateChannel -eq $true) {
                $QualifiedCount++
            } else {
                $NotQualifiedUsers.Add($User.userPrincipalName)
            }
        }

        $TotalUsers = $LicensedUsers.Count
        $ChannelPercent = if ($TotalUsers -gt 0) { [math]::Round(($QualifiedCount / $TotalUsers) * 100, 1) } else { 0 }

        if ($ChannelPercent -ge $ChannelThresholdPercent) {
            $Status = 'Passed'
            $Result = "**$QualifiedCount of $TotalUsers M365 Apps licensed users ($ChannelPercent%)** are on Current Channel or Monthly Enterprise Channel — above the $ChannelThresholdPercent% threshold.`n`n"
            $Result += 'These users will receive Copilot feature updates for desktop Word, Excel, PowerPoint, Outlook, and OneNote.'
        } else {
            $Status = 'Failed'
            $Result = "Only **$QualifiedCount of $TotalUsers M365 Apps licensed users ($ChannelPercent%)** are on a qualified update channel — below the $ChannelThresholdPercent% threshold.`n`n"
            $Result += 'Copilot in M365 desktop apps requires **Current Channel** or **Monthly Enterprise Channel**. '
            $Result += "Users on Semi-Annual Enterprise Channel or other update rings will not receive Copilot features.`n`n"
            $Result += "To remediate, update the Microsoft 365 Apps update channel via Microsoft Intune, Microsoft 365 admin center, or Group Policy.`n`n"
            if ($NotQualifiedUsers.Count -gt 0 -and $NotQualifiedUsers.Count -le 20) {
                $Result += "**Users not on a qualified update channel:**`n"
                foreach ($Upn in $NotQualifiedUsers) { $Result += "- $Upn`n" }
            } elseif ($NotQualifiedUsers.Count -gt 20) {
                $Result += "**$($NotQualifiedUsers.Count) users** are not on a qualified update channel."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady007' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Users are on a qualified M365 Apps update channel' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady007: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady007' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Users are on a qualified M365 Apps update channel' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
