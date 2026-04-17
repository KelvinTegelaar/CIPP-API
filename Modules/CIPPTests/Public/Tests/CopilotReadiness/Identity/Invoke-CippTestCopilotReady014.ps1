function Invoke-CippTestCopilotReady014 {
    <#
    .SYNOPSIS
    Tenant has enabled DLP policies to protect sensitive data (governance prerequisite for Copilot)
    #>
    param($Tenant)

    # DLP policies prevent sensitive data from being shared inappropriately. With Copilot in place,
    # DLP becomes more important — Copilot can surface sensitive content in responses. Having at
    # least one enabled DLP policy signals the tenant has begun data governance. Skipped if no
    # Purview/AIP license is present (required to run compliance PS commands).

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DlpCompliancePolicies'

        if ($null -eq $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady014' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No DLP policy data found in database. The tenant may not have a Microsoft Purview/AIP license (M365 Business Premium, E3, or E5), or data collection may not yet have run.' -Risk 'Medium' -Name 'Tenant has enabled DLP policies configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $EnabledPolicies = @($Policies | Where-Object { $_.Mode -eq 'Enable' -and $_.Enabled -eq $true })
        $AllPolicies = @($Policies)

        if ($EnabledPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = "**$($EnabledPolicies.Count) enabled DLP polic$(if ($EnabledPolicies.Count -eq 1) { 'y' } else { 'ies' })** found in the tenant.`n`n"
            $Result += "| Policy | Workload | Enabled |`n"
            $Result += "|--------|----------|---------|`n"
            foreach ($Policy in ($AllPolicies | Sort-Object DisplayName)) {
                $IsEnabled = if ($Policy.Mode -eq 'Enable' -and $Policy.Enabled -eq $true) { '✅ Yes' } else { 'No' }
                $Workload = if ($Policy.Workload) { $Policy.Workload } else { '—' }
                $Result += "| $($Policy.DisplayName) | $Workload | $IsEnabled |`n"
            }
        } else {
            $Status = 'Failed'
            $Result = "No enabled DLP policies were found in this tenant.`n`n"
            if ($AllPolicies.Count -gt 0) {
                $Result += "**$($AllPolicies.Count) polic$(if ($AllPolicies.Count -eq 1) { 'y exists' } else { 'ies exist' })** but none are enabled.`n`n"
            }
            $Result += 'Data Loss Prevention policies help protect sensitive information from being shared inappropriately — a critical control when Copilot can surface content broadly. '
            $Result += 'Enable or create DLP policies in the [Microsoft Purview compliance portal](https://compliance.microsoft.com/datalossprevention) before deploying Copilot.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady014' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Tenant has enabled DLP policies configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady014: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady014' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Tenant has enabled DLP policies configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
