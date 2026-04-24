function Invoke-CippTestCopilotReady016 {
    <#
    .SYNOPSIS
    Microsoft 365 Copilot active user count summary by app (informational, 30-day period)
    #>
    param($Tenant)

    # Reports aggregate active user counts per Copilot app (Teams, Outlook, Word, Excel, etc.)
    # for the past 30 days. Informational — shows which apps are driving Copilot adoption
    # and where engagement is low.

    try {
        $SummaryData = Get-CIPPTestData -TenantFilter $Tenant -Type 'CopilotUserCountSummary'

        if (-not $SummaryData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady016' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Copilot user count summary data found in database. Data collection may not yet have run for this tenant.' -Risk 'Informational' -Name 'Copilot active user count by app' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $Summary = if ($SummaryData -is [array]) { $SummaryData | Select-Object -First 1 } else { $SummaryData }

        # Get numeric app columns — exclude metadata fields
        $MetaFields = @('reportRefreshDate', 'reportPeriod', 'reportDate', 'id')
        $AppCounts = $Summary.PSObject.Properties | Where-Object {
            $_.Name -notin $MetaFields -and
            $null -ne $_.Value -and
            $_.Value -is [ValueType] -and
            $_.Value -isnot [bool]
        }

        $TotalAppCount = ($AppCounts | Measure-Object -Property Value -Sum).Sum ?? 0
        if (-not $AppCounts -or $TotalAppCount -eq 0) {
            $Result = "No Microsoft 365 Copilot usage was detected in the past 30 days.`n`n"
            $Result += 'This tenant either has no Copilot licenses assigned or users have not yet started using Copilot features.'
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady016' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Copilot active user count by app' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $Result = "## Copilot Active Users by App (Last 30 Days)`n`n"
        $Result += "| App | Active Users |`n"
        $Result += "|-----|-------------|`n"

        foreach ($App in ($AppCounts | Sort-Object Value -Descending)) {
            # Format the property name to be more readable — insert space before each capital
            # that follows a lowercase letter to avoid double-spacing sequences like 'AI' -> 'A I'
            $AppName = $App.Name -replace '([a-z])([A-Z])', '$1 $2' -replace 'Active Users', ''
            $Result += "| $($AppName.Trim()) | $($App.Value) |`n"
        }

        if ($Summary.reportRefreshDate) {
            $Result += "`n*Data as of $($Summary.reportRefreshDate).*"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady016' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Copilot active user count by app' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady016: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady016' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Copilot active user count by app' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
