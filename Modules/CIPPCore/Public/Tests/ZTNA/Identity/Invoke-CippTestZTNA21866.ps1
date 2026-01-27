function Invoke-CippTestZTNA21866 {
    <#
    .SYNOPSIS
    All Microsoft Entra recommendations are addressed
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21866'

    try {
        # Get directory recommendations from cache
        $Recommendations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DirectoryRecommendations'

        if (-not $Recommendations) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'All Microsoft Entra recommendations are addressed' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Monitoring'
            return
        }

        # Filter for unaddressed recommendations (active or postponed status)
        $UnaddressedRecommendations = $Recommendations | Where-Object { $_.status -in @('active', 'postponed') }

        $Passed = if ($UnaddressedRecommendations.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = '✅ All Entra Recommendations are addressed.'
        } else {
            $ResultMarkdown = "❌ Found $($UnaddressedRecommendations.Count) unaddressed Entra recommendations.`n`n"
            $ResultMarkdown += "## Unaddressed Entra recommendations`n`n"
            $ResultMarkdown += "| Display Name | Status | Insights | Priority |`n"
            $ResultMarkdown += "| :--- | :--- | :--- | :--- |`n"

            foreach ($Item in $UnaddressedRecommendations) {
                $DisplayName = $Item.displayName
                $Status = $Item.status
                $Insights = $Item.insights
                $Priority = $Item.priority
                $ResultMarkdown += "| $DisplayName | $Status | $Insights | $Priority |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'All Microsoft Entra recommendations are addressed' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'All Microsoft Entra recommendations are addressed' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
    }
}
