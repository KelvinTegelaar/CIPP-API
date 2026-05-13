function Invoke-CippTestCopilotReady015 {
    <#
    .SYNOPSIS
    Per-user Microsoft 365 Copilot usage detail (informational, 30-day period)
    #>
    param($Tenant)

    # Reports which users are actively using Copilot features across M365 apps.
    # This is purely informational — it shows who is getting value from Copilot
    # and which apps are seeing the most engagement.

    try {
        $UsageData = Get-CIPPTestData -TenantFilter $Tenant -Type 'CopilotUsageUserDetail'

        if (-not $UsageData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady015' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot usage data found in database. Data collection may not yet have run for this tenant.' -Risk 'Informational' -Name 'Microsoft 365 Copilot usage per user' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $ActiveUsers = @($UsageData | Where-Object { $_.userPrincipalName -and $_.userPrincipalName -ne 'Not applicable' })

        if ($ActiveUsers.Count -eq 0) {
            $Result = "No Microsoft 365 Copilot usage was detected in the past 30 days.`n`n"
            $Result += 'This tenant either has no Copilot licenses assigned, or users have not yet started using Copilot features. '
            $Result += 'See tests CopilotReady001 and CopilotReady002 to check licensing status.'
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady015' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Microsoft 365 Copilot usage per user' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Determine which app columns are present
        $SampleUser = $ActiveUsers | Select-Object -First 1
        $AppColumns = $SampleUser.PSObject.Properties.Name | Where-Object {
            $_ -notin @('userPrincipalName', 'displayName', 'lastActivityDate', 'reportRefreshDate', 'reportPeriod', 'id')
        }

        $Result = "**$($ActiveUsers.Count) users** had Copilot activity in the past 30 days.`n`n"

        # Build table header from available columns
        $Headers = @('User', 'Last Active') + $AppColumns
        $Result += '| ' + ($Headers -join ' | ') + " |`n"
        $Result += '| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + " |`n"

        $DisplayUsers = $ActiveUsers | Sort-Object lastActivityDate -Descending | Select-Object -First 50
        foreach ($User in $DisplayUsers) {
            $LastActive = if ($User.lastActivityDate) { $User.lastActivityDate } else { 'N/A' }
            $Row = "| $($User.userPrincipalName) | $LastActive |"
            foreach ($Col in $AppColumns) {
                $Val = $User.$Col
                $Row += " $Val |"
            }
            $Result += "$Row`n"
        }

        if ($ActiveUsers.Count -gt 50) {
            $Result += "`n*Showing 50 of $($ActiveUsers.Count) active users.*"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady015' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Microsoft 365 Copilot usage per user' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady015: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady015' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Microsoft 365 Copilot usage per user' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
