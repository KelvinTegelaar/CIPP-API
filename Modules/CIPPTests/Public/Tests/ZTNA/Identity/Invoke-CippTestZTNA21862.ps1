function Invoke-CippTestZTNA21862 {
    <#
    .SYNOPSIS
    All risky workload identities are triaged
    #>
    param($Tenant)

    $TestId = 'ZTNA21862'
    #Tested
    try {
        # Get risky service principals and risk detections from cache
        $UntriagedRiskyPrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'RiskyServicePrincipals' | Where-Object { $_.riskState -eq 'atRisk' }
        $ServicePrincipalRiskDetections = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipalRiskDetections'
        $UntriagedRiskDetections = $ServicePrincipalRiskDetections | Where-Object { $_.riskState -eq 'atRisk' }

        if (-not $UntriagedRiskyPrincipals -and -not $ServicePrincipalRiskDetections) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'All risky workload identities are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
            return
        }

        $Passed = if (($UntriagedRiskyPrincipals.Count -eq 0) -and ($UntriagedRiskDetections.Count -eq 0)) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = '✅ All risky workload identities have been triaged'
        } else {
            $RiskySPCount = $UntriagedRiskyPrincipals.Count
            $RiskyDetectionCount = $UntriagedRiskDetections.Count
            $ResultMarkdown = "❌ Found $RiskySPCount untriaged risky service principals and $RiskyDetectionCount untriaged risk detections`n`n"

            if ($RiskySPCount -gt 0) {
                $ResultMarkdown += "## Untriaged Risky Service Principals`n`n"
                $ResultMarkdown += "| Service Principal | Type | Risk Level | Risk State | Risk Last Updated |`n"
                $ResultMarkdown += "| :--- | :--- | :--- | :--- | :--- |`n"
                foreach ($SP in $UntriagedRiskyPrincipals) {
                    $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/SignOn/objectId/$($SP.id)/appId/$($SP.appId)"
                    $RiskLevel = switch ($SP.riskLevel) {
                        'high' { '🔴 High' }
                        'medium' { '🟡 Medium' }
                        'low' { '🟢 Low' }
                        default { $SP.riskLevel }
                    }
                    $RiskState = switch ($SP.riskState) {
                        'atRisk' { '⚠️ At Risk' }
                        'confirmedCompromised' { '🔴 Confirmed Compromised' }
                        'dismissed' { '✅ Dismissed' }
                        'remediated' { '✅ Remediated' }
                        default { $SP.riskState }
                    }
                    $ResultMarkdown += "| [$($SP.displayName)]($PortalLink) | $($SP.servicePrincipalType) | $RiskLevel | $RiskState | $($SP.riskLastUpdatedDateTime) |`n"
                }
            }

            if ($RiskyDetectionCount -gt 0) {
                $ResultMarkdown += "`n`n## Untriaged Risk Detection Events`n`n"
                $ResultMarkdown += "| Service Principal | Risk Level | Risk State | Risk Event Type | Risk Last Updated |`n"
                $ResultMarkdown += "| :--- | :--- | :--- | :--- | :--- |`n"
                foreach ($Detection in $UntriagedRiskDetections) {
                    $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/SignOn/objectId/$($Detection.servicePrincipalId)/appId/$($Detection.appId)"
                    $RiskLevel = switch ($Detection.riskLevel) {
                        'high' { '🔴 High' }
                        'medium' { '🟡 Medium' }
                        'low' { '🟢 Low' }
                        default { $Detection.riskLevel }
                    }
                    $RiskState = switch ($Detection.riskState) {
                        'atRisk' { '⚠️ At Risk' }
                        'confirmedCompromised' { '🔴 Confirmed Compromised' }
                        'dismissed' { '✅ Dismissed' }
                        'remediated' { '✅ Remediated' }
                        default { $Detection.riskState }
                    }
                    $ResultMarkdown += "| [$($Detection.servicePrincipalDisplayName)]($PortalLink) | $RiskLevel | $RiskState | $($Detection.riskEventType) | $($Detection.detectedDateTime) |`n"
                }
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'All risky workload identities are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All risky workload identities are triaged' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Monitoring'
    }
}
