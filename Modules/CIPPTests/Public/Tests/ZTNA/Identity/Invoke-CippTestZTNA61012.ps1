function Invoke-CippTestZTNA61012 {
    <#
    .SYNOPSIS
    Risk-based Conditional Access blocks risky agent identities
    #>
    param($Tenant)

    $TestId = 'ZTNA61012'
    $Name = 'Risk-based Conditional Access blocks risky agent identities'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset EntraP2 -SkipLog) -or
            -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -RequiredCapabilities 'AGENT_365' -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for risk-based Conditional Access for agents. Required capabilities: AAD_PREMIUM_P2 and AGENT_365.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Conditional Access policies found in database. Data collection may not have completed yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
            return
        }

        $AgentIdentityPolicies = $Policies.Where({
                [bool]$_.conditions.clientApplications.includeAgentIdServicePrincipals -or
                -not [string]::IsNullOrWhiteSpace($_.conditions.clientApplications.agentIdServicePrincipalFilter.rule)
            })
        $Blocking = $AgentIdentityPolicies.Where({
                $_.state -eq 'enabled' -and
                ([string]$_.conditions.agentIdRiskLevels -split ',') -contains 'high' -and
                @($_.grantControls.builtInControls) -contains 'block'
            })

        $Status = if ($Blocking.Count -ge 1) { 'Passed' } else { 'Failed' }
        $Result = [System.Text.StringBuilder]::new()
        if ($Status -eq 'Passed') {
            [void]$Result.Append("The tenant has at least one enabled risk-based Conditional Access policy that blocks high-risk agent identities.`n")
        } else {
            [void]$Result.Append("The tenant does not have an enabled risk-based Conditional Access policy that blocks high-risk agent identities. Microsoft Entra ID Protection signals may be produced for risky agents, but access is not blocked by a qualifying Conditional Access policy.`n")
        }

        if ($AgentIdentityPolicies.Count -gt 0) {
            [void]$Result.Append("`n## [Risk-based Conditional Access policies for agent principals](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)`n`n")
            [void]$Result.Append("| Policy | State | Agent risk level | Grant controls | Status |`n")
            [void]$Result.Append("| :----- | :---- | :--------------- | :------------- | :----- |`n")
            foreach ($Policy in $AgentIdentityPolicies) {
                $RiskLevels = [string]$Policy.conditions.agentIdRiskLevels
                $RiskLabel = if (-not $RiskLevels) { '❌ Not configured' } elseif (($RiskLevels -split ',') -contains 'high') { "✅ $RiskLevels" } else { "❌ $RiskLevels" }
                $Controls = @($Policy.grantControls.builtInControls).Where({ $_ }) -join ', '
                $ControlsLabel = if (-not $Controls) { '❌ None' } elseif (@($Policy.grantControls.builtInControls) -contains 'block') { "✅ $Controls" } else { "❌ $Controls" }
                $RowStatus = if ($Blocking.Contains($Policy)) { '✅ Pass' } else { '❌ Fail' }
                [void]$Result.Append("| [$($Policy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)) | $($Policy.state) | $RiskLabel | $ControlsLabel | $RowStatus |`n")
            }
        } else {
            [void]$Result.Append("`nNo Conditional Access policies targeting agent identities were found.`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Authentication & Access'
    }
}
