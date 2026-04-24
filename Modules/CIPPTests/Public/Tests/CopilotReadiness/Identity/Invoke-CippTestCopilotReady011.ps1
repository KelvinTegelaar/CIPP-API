function Invoke-CippTestCopilotReady011 {
    <#
    .SYNOPSIS
    Tenant has at least one enabled Conditional Access policy (security prerequisite for Copilot)
    #>
    param($Tenant)

    # CA policies are a key security control before deploying Copilot. Without CA, there is no
    # baseline enforcement of MFA at sign-in, device compliance, or location-based access controls.
    # Pass if at least one CA policy with state = 'enabled' exists.
    # Skipped if the tenant does not have Azure AD Premium (no CA capability).

    try {
        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady011' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Conditional Access policy data found in database. The tenant may not have Azure AD Premium, or data collection may not yet have run.' -Risk 'High' -Name 'Tenant has enabled Conditional Access policies' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $EnabledPolicies = @($CAPolicies | Where-Object { $_.state -eq 'enabled' })
        $ReportOnlyPolicies = @($CAPolicies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' })

        if ($EnabledPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = "**$($EnabledPolicies.Count) enabled Conditional Access polic$(if ($EnabledPolicies.Count -eq 1) { 'y' } else { 'ies' })** found in the tenant.`n`n"
            $Result += "| Policy Name | State |`n"
            $Result += "|-------------|-------|`n"
            foreach ($Policy in ($EnabledPolicies | Sort-Object displayName)) {
                $Result += "| $($Policy.displayName) | Enabled |`n"
            }
            if ($ReportOnlyPolicies.Count -gt 0) {
                $Result += "`n*$($ReportOnlyPolicies.Count) additional polic$(if ($ReportOnlyPolicies.Count -eq 1) { 'y is' } else { 'ies are' }) in report-only mode and not enforcing access controls.*"
            }
        } else {
            $Status = 'Failed'
            $Result = "No enabled Conditional Access policies were found in this tenant.`n`n"
            if ($ReportOnlyPolicies.Count -gt 0) {
                $Result += "**$($ReportOnlyPolicies.Count) polic$(if ($ReportOnlyPolicies.Count -eq 1) { 'y is' } else { 'ies are' }) in report-only mode** but not enforcing.`n`n"
            }
            $Result += 'Conditional Access is the primary mechanism for enforcing MFA, device compliance, and access controls in Entra ID. '
            $Result += 'Before deploying Copilot, establish at least a baseline CA policy requiring MFA for all users. '
            $Result += 'See [Microsoft CA policy templates](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common) to get started.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady011' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Tenant has enabled Conditional Access policies' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady011: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady011' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Tenant has enabled Conditional Access policies' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
