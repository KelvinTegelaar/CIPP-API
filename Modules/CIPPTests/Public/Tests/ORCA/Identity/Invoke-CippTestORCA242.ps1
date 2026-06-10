function Invoke-CippTestORCA242 {
    <#
    .SYNOPSIS
    Important protection alerts enabled
    #>
    param($Tenant)

    try {
        $Alerts = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoProtectionAlert'

        if (-not $Alerts) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA242' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No protection alert data found. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Important protection alerts enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Configuration'
            return
        }

        # ORCA-242: alerts that drive Automated Incident Response (AIR).
        # Alerts not present in the tenant are skipped (Microsoft hasn't deployed them).
        $ImportantAlerts = @(
            'A potentially malicious URL click was detected'
            'Teams message reported by user as security risk'
            'Email messages containing phish URLs removed after delivery'
            'Suspicious Email Forwarding Activity'
            'Malware not zapped because ZAP is disabled'
            'Phish delivered due to an ETR override'
            'Email messages containing malicious file removed after delivery'
            'Email reported by user as malware or phish'
            'Email messages containing malicious URL removed after delivery'
            'Email messages containing malware removed after delivery'
            'A user clicked through to a potentially malicious URL'
            'Email messages from a campaign removed after delivery'
            'Email messages removed after delivery'
            'Suspicious email sending patterns detected'
        )

        $FailedAlerts = [System.Collections.Generic.List[object]]::new()
        $PassedAlerts = [System.Collections.Generic.List[object]]::new()

        foreach ($AlertName in $ImportantAlerts) {
            $Found = $Alerts | Where-Object { $_.Name -eq $AlertName } | Select-Object -First 1
            if ($null -eq $Found) { continue }

            if ($Found.Disabled -eq $true) {
                $FailedAlerts.Add($Found) | Out-Null
            } else {
                $PassedAlerts.Add($Found) | Out-Null
            }
        }

        if ($FailedAlerts.Count -eq 0 -and $PassedAlerts.Count -eq 0) {
            $Status = 'Skipped'
            $Result = [System.Text.StringBuilder]::new('None of the AIR-related protection alerts are deployed to this tenant. This may indicate missing Defender for Office 365 licensing.')
        } elseif ($FailedAlerts.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All AIR-related protection alerts deployed to this tenant are enabled.`n`n")
            $null = $Result.Append("**Enabled Alerts:** $($PassedAlerts.Count)`n`n")
            $null = $Result.Append("| Alert Name |`n|------------|`n")
            foreach ($Alert in $PassedAlerts) {
                $null = $Result.Append("| $($Alert.Name) |`n")
            }
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedAlerts.Count) AIR-related protection alerts are disabled.`n`n")
            $null = $Result.Append("**Disabled:** $($FailedAlerts.Count) | **Enabled:** $($PassedAlerts.Count)`n`n")
            $null = $Result.Append("### Disabled Alerts`n`n")
            $null = $Result.Append("| Alert Name | Disabled |`n|------------|----------|`n")
            foreach ($Alert in $FailedAlerts) {
                $null = $Result.Append("| $($Alert.Name) | $($Alert.Disabled) |`n")
            }
            $null = $Result.Append("`n**Remediation:** Re-enable these alert policies. Automated Incident Response (AIR) triggers from them and cannot function correctly when they are disabled.")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA242' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Important protection alerts enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA242' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Important protection alerts enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Configuration'
    }
}
