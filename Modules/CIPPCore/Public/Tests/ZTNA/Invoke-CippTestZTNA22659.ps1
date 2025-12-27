function Invoke-CippTestZTNA22659 {
    <#
    .SYNOPSIS
    Checks if risky workload identity sign-ins have been triaged

    .DESCRIPTION
    Verifies that there are no active risky sign-in detections for service principals,
    ensuring that compromised workload identities are properly investigated and remediated.

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
        # Get service principal risk detections from cache
        $RiskDetections = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipalRiskDetections'

        if (-not $RiskDetections) {
            $TestParams = @{
                TestId               = 'ZTNA22659'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve service principal risk detections from cache.'
                Risk                 = 'High'
                Name                 = 'Triage risky workload identity sign-ins'
                UserImpact           = 'High'
                ImplementationEffort = 'Low'
                Category             = 'Identity protection'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Filter for sign-in detections that are at risk
        $RiskySignIns = [System.Collections.Generic.List[object]]::new()
        foreach ($detection in $RiskDetections) {
            if ($detection.activity -eq 'signIn' -and $detection.riskState -eq 'atRisk') {
                $RiskySignIns.Add($detection)
            }
        }

        $Status = if ($RiskySignIns.Count -eq 0) { 'Passed' } else { 'Failed' }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: No risky workload identity sign-ins detected or all have been triaged.`n`n"
            $ResultMarkdown += '[View identity protection](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyServicePrincipals)'
        } else {
            $ResultMarkdown = "❌ **Fail**: There are $($RiskySignIns.Count) risky workload identity sign-in(s) that require investigation.`n`n"
            $ResultMarkdown += "## Risky service principal sign-ins`n`n"
            $ResultMarkdown += "| Service Principal | App ID | Risk State | Risk Level | Last Updated |`n"
            $ResultMarkdown += "| :---------------- | :----- | :--------- | :--------- | :----------- |`n"

            foreach ($signin in $RiskySignIns) {
                $spName = if ($signin.servicePrincipalDisplayName) { $signin.servicePrincipalDisplayName } else { 'N/A' }
                $appId = if ($signin.appId) { $signin.appId } else { 'N/A' }
                $riskState = if ($signin.riskState) { $signin.riskState } else { 'N/A' }
                $riskLevel = if ($signin.riskLevel) { $signin.riskLevel } else { 'N/A' }

                # Format last updated date
                $lastUpdated = 'N/A'
                if ($signin.lastUpdatedDateTime) {
                    try {
                        $date = [DateTime]::Parse($signin.lastUpdatedDateTime)
                        $lastUpdated = $date.ToString('yyyy-MM-dd HH:mm')
                    } catch {
                        $lastUpdated = $signin.lastUpdatedDateTime
                    }
                }

                $ResultMarkdown += "| $spName | $appId | $riskState | $riskLevel | $lastUpdated |`n"
            }

            $ResultMarkdown += "`n[Investigate and remediate](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/IdentityProtectionMenuBlade/~/RiskyServicePrincipals)"
        }

        $TestParams = @{
            TestId               = 'ZTNA22659'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'Triage risky workload identity sign-ins'
            UserImpact           = 'High'
            ImplementationEffort = 'Low'
            Category             = 'Identity protection'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA22659'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'Triage risky workload identity sign-ins'
            UserImpact           = 'High'
            ImplementationEffort = 'Low'
            Category             = 'Identity protection'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA22659 failed: $($_.Exception.Message)" -sev Error
    }
}
