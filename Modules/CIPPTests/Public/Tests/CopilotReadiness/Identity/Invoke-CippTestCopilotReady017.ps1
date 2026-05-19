function Invoke-CippTestCopilotReady017 {
    <#
    .SYNOPSIS
    Microsoft 365 Copilot active user count trend - is adoption growing or declining?
    #>
    param($Tenant)

    # Uses the 7-day trend report to determine whether Copilot active user counts are
    # growing, stable, or declining. Compares the most recent day to the earliest day
    # in the trend window. Declining trend is flagged as a warning — it may indicate
    # user disengagement with Copilot and may warrant an adoption campaign.

    try {
        $TrendData = Get-CIPPTestData -TenantFilter $Tenant -Type 'CopilotUserCountTrend'

        if (-not $TrendData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady017' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot user count trend data found in database. Data collection may not yet have run for this tenant.' -Risk 'Informational' -Name 'Copilot adoption trend (7-day)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $TrendPoints = @($TrendData | Where-Object { $_.reportDate } | Sort-Object reportDate)

        if ($TrendPoints.Count -eq 0) {
            $Result = "No Microsoft 365 Copilot usage trend data was found for the past 7 days.`n`n"
            $Result += 'This tenant either has no Copilot licenses assigned or users have not yet started using Copilot features.'
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady017' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Copilot adoption trend (7-day)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        # Find a consistent active user count field
        $CountField = $TrendPoints[0].PSObject.Properties.Name | Where-Object {
            $_ -notmatch 'report|date|id' -and $TrendPoints[0].$_ -match '^\d+$'
        } | Select-Object -First 1

        # Build trend table
        $Result = "## Copilot Active User Trend (Last 7 Days)`n`n"
        $Result += "| Date | Active Users |`n"
        $Result += "|------|-------------|`n"

        foreach ($Point in $TrendPoints) {
            $Count = if ($CountField) { $Point.$CountField } else { 'N/A' }
            $Result += "| $($Point.reportDate) | $Count |`n"
        }

        # Determine trend direction if we have a count field and at least 2 data points
        $Status = 'Informational'
        if ($CountField -and $TrendPoints.Count -ge 2) {
            $Earliest = [int]($TrendPoints[0].$CountField)
            $Latest = [int]($TrendPoints[-1].$CountField)
            $Delta = $Latest - $Earliest

            if ($Delta -gt 0) {
                $TrendIcon = '📈'
                $TrendText = "**Trending up** — active Copilot users increased by $Delta over the 7-day window."
            } elseif ($Delta -eq 0) {
                $TrendIcon = '➡️'
                $TrendText = '**Stable** — active Copilot user count is unchanged over the 7-day window.'
            } else {
                $TrendIcon = '📉'
                $TrendText = "**Trending down** — active Copilot users decreased by $([math]::Abs($Delta)) over the 7-day window. Consider reviewing adoption activities to re-engage users."
            }

            $Result += "`n$TrendIcon $TrendText"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady017' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Informational' -Name 'Copilot adoption trend (7-day)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady017: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady017' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Copilot adoption trend (7-day)' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
