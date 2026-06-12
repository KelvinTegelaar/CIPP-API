function Invoke-CippTestZTNA21864 {
    <#
    .SYNOPSIS
    All risk detections are triaged
    #>
    param($Tenant)

    try {
        $RiskDetections = Get-CIPPTestData -TenantFilter $Tenant -Type 'RiskDetections'

        if (-not $RiskDetections) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21864' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'All risk detections are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Access Control'
            return
        }

        # Risk detections that haven't been actioned. Anything still in atRisk/unknownFutureValue
        # older than 30 days is untriaged.
        $TriagedStates = 'remediated', 'dismissed', 'confirmedSafe', 'none'
        $Threshold = (Get-Date).AddDays(-30)

        $Untriaged = [System.Collections.Generic.List[object]]::new()
        foreach ($Detection in $RiskDetections) {
            if ($Detection.riskState -in $TriagedStates) { continue }
            $When = $Detection.detectedDateTime ?? $Detection.activityDateTime
            if (-not $When) { continue }
            try {
                if (([DateTime]$When) -lt $Threshold) { $Untriaged.Add($Detection) }
            } catch { }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Untriaged.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $($RiskDetections.Count) risk detection(s) have been triaged or are recent (within 30 days).")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($Untriaged.Count) risk detection(s) older than 30 days remain in an untriaged state.")
            $Lines.Add('')
            $Lines.Add("**Total detections:** $($RiskDetections.Count)")
            $Lines.Add("**Untriaged (>30 days):** $($Untriaged.Count)")
            $Lines.Add('')
            $Lines.Add('| User | Risk Event | Risk Level | Risk State | Detected |')
            $Lines.Add('| :--- | :--------- | :--------- | :--------- | :------- |')
            $Top = $Untriaged | Sort-Object { [DateTime]($_.detectedDateTime ?? $_.activityDateTime) } | Select-Object -First 25
            foreach ($D in $Top) {
                $When = ($D.detectedDateTime ?? $D.activityDateTime)
                $Lines.Add("| $($D.userDisplayName ?? '-') | $($D.riskEventType ?? '-') | $($D.riskLevel ?? '-') | $($D.riskState ?? '-') | $When |")
            }
            if ($Untriaged.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($Untriaged.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Investigate and triage the listed risk detections through the Microsoft Entra ID Protection portal. Resolve each by marking the user as compromised, dismissing, or confirming safe.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21864' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'High' -Name 'All risk detections are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21864' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All risk detections are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Access Control'
    }
}
