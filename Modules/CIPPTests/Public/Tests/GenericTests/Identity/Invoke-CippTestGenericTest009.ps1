function Invoke-CippTestGenericTest009 {
    <#
    .SYNOPSIS
    Secure Score Report — 14-day trend of Microsoft Secure Score
    #>
    param($Tenant)

    try {
        $SecureScoreData = Get-CIPPTestData -TenantFilter $Tenant -Type 'SecureScore'

        if (-not $SecureScoreData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest009' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Secure Score data found in the reporting database. Please sync the Secure Score cache first.' -Risk 'Informational' -Name 'Secure Score Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Scores = @($SecureScoreData | Where-Object { $_.currentScore -ne $null })
        if ($Scores.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest009' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'Secure Score data was found but contained no score records.' -Risk 'Informational' -Name 'Secure Score Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        # Sort by date ascending for trend display
        $SortedScores = $Scores | Sort-Object { if ($_.createdDateTime) { [datetime]$_.createdDateTime } else { [datetime]::MinValue } }

        $Latest = $SortedScores | Select-Object -Last 1
        $Oldest = $SortedScores | Select-Object -First 1
        $CurrentScore = [math]::Round([double]$Latest.currentScore, 1)
        $MaxScore = [math]::Round([double]$Latest.maxScore, 1)
        $ScorePct = if ($MaxScore -gt 0) { [math]::Round(($CurrentScore / $MaxScore) * 100, 1) } else { 0 }

        $OldestScore = [math]::Round([double]$Oldest.currentScore, 1)
        $ScoreChange = [math]::Round($CurrentScore - $OldestScore, 1)
        $TrendIcon = if ($ScoreChange -gt 0) { "📈 +$ScoreChange" } elseif ($ScoreChange -lt 0) { "📉 $ScoreChange" } else { '➡️ No change' }

        $Result = "### Current Score`n`n"
        $Result += "| Metric | Value |`n"
        $Result += "|--------|-------|`n"
        $Result += "| Current Score | **$CurrentScore** out of $MaxScore ($ScorePct%) |`n"
        $Result += "| 14-Day Trend | $TrendIcon |`n"
        $Result += "| Data Points | $($SortedScores.Count) days |`n`n"

        if ($ScorePct -ge 80) {
            $Result += "**✅ Strong security posture.** Your score is in the top tier. Keep monitoring to maintain this level.`n`n"
        } elseif ($ScorePct -ge 50) {
            $Result += "**🟡 Moderate security posture.** There's room for improvement. Review the recommended actions in your Microsoft 365 Security portal.`n`n"
        } else {
            $Result += "**🔴 Low security posture.** Significant improvements are recommended. Focus on the high-impact actions first.`n`n"
        }

        $Result += "### 14-Day Score Trend`n`n"
        $Result += "| Date | Score | Max Score | Percentage |`n"
        $Result += "|------|-------|-----------|------------|`n"

        foreach ($Score in $SortedScores) {
            $DateStr = if ($Score.createdDateTime) { ([datetime]$Score.createdDateTime).ToString('yyyy-MM-dd') } else { 'Unknown' }
            $DayScore = [math]::Round([double]$Score.currentScore, 1)
            $DayMax = [math]::Round([double]$Score.maxScore, 1)
            $DayPct = if ($DayMax -gt 0) { [math]::Round(($DayScore / $DayMax) * 100, 1) } else { 0 }
            $Result += "| $DateStr | $DayScore | $DayMax | $DayPct% |`n"
        }

        # Show top improvable controls if available
        if ($Latest.controlScores) {
            $Controls = if ($Latest.controlScores -is [string]) {
                try { $Latest.controlScores | ConvertFrom-Json } catch { @() }
            } else { $Latest.controlScores }

            $ImprovableControls = @($Controls | Where-Object { $_.score -ne $null } | ForEach-Object {
                $MaxControlScore = if ($_.maxScore) { [double]$_.maxScore } else { 0 }
                $CurrentControlScore = [double]$_.score
                $Gap = $MaxControlScore - $CurrentControlScore
                [PSCustomObject]@{
                    Name        = $_.controlName -replace '([a-z])([A-Z])', '$1 $2'
                    Score       = $CurrentControlScore
                    MaxScore    = $MaxControlScore
                    Gap         = $Gap
                    Description = $_.description
                }
            } | Where-Object { $_.Gap -gt 0 } | Sort-Object Gap -Descending | Select-Object -First 10)

            if ($ImprovableControls.Count -gt 0) {
                $Result += "`n### Top Improvement Opportunities`n`n"
                $Result += "| Control | Current | Max | Points Available |`n"
                $Result += "|---------|---------|-----|-----------------|`n"

                foreach ($Control in $ImprovableControls) {
                    $Result += "| $($Control.Name) | $($Control.Score) | $($Control.MaxScore) | +$($Control.Gap) |`n"
                }
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest009' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Secure Score Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest009: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest009' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Secure Score Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
