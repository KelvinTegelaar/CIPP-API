function Invoke-CippTestZTNA21863 {
    <#
    .SYNOPSIS
    All high-risk sign-ins are triaged
    #>
    param($Tenant)

    $TestId = 'ZTNA21863'
    #Tested
    try {
        # Get risk detections from cache and filter for high-risk untriaged sign-ins
        $RiskDetections = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RiskDetections'

        if (-not $RiskDetections) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'All high-risk sign-ins are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
            return
        }

        $UntriagedHighRiskSignIns = $RiskDetections | Where-Object { $_.riskState -eq 'atRisk' -and $_.riskLevel -eq 'high' }

        $Passed = if ($UntriagedHighRiskSignIns.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = '✅ No untriaged risky sign ins in the tenant.'
        } else {
            $ResultMarkdown = "❌ Found **$($UntriagedHighRiskSignIns.Count)** untriaged high-risk sign ins.`n`n"
            $ResultMarkdown += "## Untriaged High-Risk Sign ins`n`n"
            $ResultMarkdown += "| Date | User Principal Name | Type | Risk Level |`n"
            $ResultMarkdown += "| :---- | :---- | :---- | :---- |`n"

            foreach ($Risk in $UntriagedHighRiskSignIns) {
                $UserPrincipalName = $Risk.userPrincipalName
                $RiskLevel = switch ($Risk.riskLevel) {
                    'high' { '🔴 High' }
                    'medium' { '🟡 Medium' }
                    'low' { '🟢 Low' }
                    default { $Risk.riskLevel }
                }
                $RiskEventType = $Risk.riskEventType
                $RiskDate = $Risk.detectedDateTime
                $ResultMarkdown += "| $RiskDate | $UserPrincipalName | $RiskEventType | $RiskLevel |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'All high-risk sign-ins are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All high-risk sign-ins are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
    }
}
