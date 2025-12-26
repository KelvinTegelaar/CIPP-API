function Invoke-CippTestZTNA22124 {
    <#
    .SYNOPSIS
    Checks if all high priority Entra recommendations have been addressed

    .DESCRIPTION
    Verifies that there are no active or postponed high priority recommendations in the tenant,
    ensuring critical security improvements have been implemented.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested
    try {
        # Get directory recommendations from cache
        $Recommendations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DirectoryRecommendations'

        if (-not $Recommendations) {
            $TestParams = @{
                TestId               = 'ZTNA22124'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve directory recommendations from cache.'
                Risk                 = 'High'
                Name                 = 'Address high priority Entra recommendations'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Governance'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Filter for high priority recommendations that are active or postponed
        $HighPriorityIssues = [System.Collections.Generic.List[object]]::new()
        foreach ($rec in $Recommendations) {
            if ($rec.priority -eq 'high' -and ($rec.status -eq 'active' -or $rec.status -eq 'postponed')) {
                $HighPriorityIssues.Add($rec)
            }
        }

        $Status = if ($HighPriorityIssues.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: All high priority Entra recommendations have been addressed.`n`n"
            $ResultMarkdown += '[View recommendations](https://entra.microsoft.com/#view/Microsoft_Azure_SecureScore/OverviewBlade)'
        } else {
            $ResultMarkdown = "❌ **Fail**: There are $($HighPriorityIssues.Count) high priority recommendation(s) that have not been addressed.`n`n"
            $ResultMarkdown += "## Outstanding high priority recommendations`n`n"
            $ResultMarkdown += "| Display Name | Status | Insights |`n"
            $ResultMarkdown += "| :----------- | :----- | :------- |`n"

            foreach ($issue in $HighPriorityIssues) {
                $displayName = if ($issue.displayName) { $issue.displayName } else { 'N/A' }
                $status = if ($issue.status) { $issue.status } else { 'N/A' }
                $insights = if ($issue.insights) { $issue.insights } else { 'N/A' }
                $ResultMarkdown += "| $displayName | $status | $insights |`n"
            }

            $ResultMarkdown += "`n[Address recommendations](https://entra.microsoft.com/#view/Microsoft_Azure_SecureScore/OverviewBlade)"
        }

        $TestParams = @{
            TestId               = 'ZTNA22124'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'Address high priority Entra recommendations'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Governance'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA22124'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'Address high priority Entra recommendations'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Governance'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA22124 failed: $($_.Exception.Message)" -sev Error
    }
}
