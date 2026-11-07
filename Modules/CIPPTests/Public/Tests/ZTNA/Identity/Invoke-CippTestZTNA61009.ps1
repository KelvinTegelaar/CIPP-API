function Invoke-CippTestZTNA61009 {
    <#
    .SYNOPSIS
    Conditional Access policies cover both agent identities and agent users
    #>
    param($Tenant)

    $TestId = 'ZTNA61009'
    $Name = 'Conditional Access policies cover both agent identities and agent users'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog) -or
            -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -RequiredCapabilities 'AGENT_365' -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Conditional Access for agents. Required capabilities: AAD_PREMIUM or AAD_PREMIUM_P2, and AGENT_365.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Identity & Access'
            return
        }

        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Conditional Access policies found in database. Data collection may not have completed yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Identity & Access'
            return
        }

        $AgentIdentityPolicies = $Policies.Where({
                [bool]$_.conditions.clientApplications.includeAgentIdServicePrincipals -or
                -not [string]::IsNullOrEmpty($_.conditions.clientApplications.agentIdServicePrincipalFilter.rule)
            })
        # Graph stores agent-user targeting in conditions.agents; upstream checks the includeUsers token, so both count.
        $AgentUserPolicies = $Policies.Where({
                @($_.conditions.users.includeUsers) -contains 'AllAgentIdUsers' -or
                [bool]$_.conditions.agents.includeAgentUsers
            })
        $IsBlocking = { $_.state -eq 'enabled' -and @($_.grantControls.builtInControls) -contains 'block' }
        $IdentityBlocking = $AgentIdentityPolicies.Where($IsBlocking)
        $UserBlocking = $AgentUserPolicies.Where($IsBlocking)

        $Status = if ($IdentityBlocking.Count -ge 1 -and $UserBlocking.Count -ge 1) { 'Passed' } else { 'Failed' }
        $Result = [System.Text.StringBuilder]::new()
        if ($Status -eq 'Passed') {
            [void]$Result.Append("At least one enabled Conditional Access policy blocks agent identities, and at least one enabled Conditional Access policy blocks agent users.`n")
        } else {
            [void]$Result.Append("No enabled Conditional Access policy targets agent identities with the ``block`` control, OR no enabled Conditional Access policy targets agent users with the ``block`` control. Agent traffic for the uncovered principal type bypasses Conditional Access enforcement.`n")
        }

        $Rows = @(
            foreach ($Policy in $AgentIdentityPolicies) {
                $ClientApps = $Policy.conditions.clientApplications
                $Targeted = if (@($ClientApps.includeAgentIdServicePrincipals) -contains 'All' -and -not $ClientApps.excludeAgentIdServicePrincipals) { 'All Agent Identities' } else { 'Some Agent Identities or Blueprints' }
                @{ Policy = $Policy; Targeted = $Targeted; Blocking = $IdentityBlocking.Contains($Policy) }
            }
            foreach ($Policy in $AgentUserPolicies) { @{ Policy = $Policy; Targeted = 'Agent Users'; Blocking = $UserBlocking.Contains($Policy) } }
        )
        if ($Rows.Count -gt 0) {
            [void]$Result.Append("`n### [Conditional Access policies covering agent principals](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)`n`n")
            [void]$Result.Append("| Policy | Targeted Agent Identity types | State | Grant controls | Status |`n")
            [void]$Result.Append("| :----- | :---------------------------- | :---- | :------------- | :----- |`n")
            foreach ($Row in $Rows) {
                $Policy = $Row.Policy
                $Grants = if ($Policy.grantControls.builtInControls) { @($Policy.grantControls.builtInControls) -join ', ' } else { '(none)' }
                $RowStatus = if ($Row.Blocking) { '✅ Pass' } else { '❌ Fail' }
                [void]$Result.Append("| [$($Policy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)) | $($Row.Targeted) | $($Policy.state) | $Grants | $RowStatus |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result.ToString() -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Identity & Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'AI Identity & Access'
    }
}
