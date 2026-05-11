function Invoke-CippTestCopilotReady013 {
    <#
    .SYNOPSIS
    Tenant has active sensitivity labels configured in Microsoft Purview
    #>
    param($Tenant)

    # Sensitivity labels are a governance control that helps classify and protect data before
    # Copilot is deployed. Copilot respects sensitivity labels when generating content and can
    # apply labels to created documents. Having labels configured means the tenant has a data
    # classification framework in place. Skipped if no Purview/AIP license is present.

    try {
        $Labels = Get-CIPPTestData -TenantFilter $Tenant -Type 'SensitivityLabels'

        if ($null -eq $Labels) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady013' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No sensitivity label data found in database. The tenant may not have a Microsoft Purview/AIP license (M365 Business Premium, E3, or E5), or data collection may not yet have run.' -Risk 'Medium' -Name 'Tenant has sensitivity labels configured in Purview' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        $ActiveLabels = @($Labels | Where-Object { $_.isActive -eq $true })

        if ($ActiveLabels.Count -gt 0) {
            $Status = 'Passed'
            $Result = "**$($ActiveLabels.Count) active sensitivity label$(if ($ActiveLabels.Count -eq 1) { '' } else { 's' })** found in the tenant.`n`n"
            $Result += "| Label | Parent | Has Protection |`n"
            $Result += "|-------|--------|---------------|`n"
            foreach ($Label in ($ActiveLabels | Sort-Object sensitivity)) {
                $ParentName = if ($Label.parent -and $Label.parent.name) { $Label.parent.name } else { '—' }
                $HasProtection = if ($Label.hasProtection -eq $true) { '✅ Yes' } else { 'No' }
                $Result += "| $($Label.name) | $ParentName | $HasProtection |`n"
            }
            $Result += "`nCopilot can respect and apply these labels when creating or summarizing content."
        } else {
            $Status = 'Failed'
            $Result = "No active sensitivity labels were found in this tenant.`n`n"
            $Result += 'Sensitivity labels classify and protect organizational data — helping ensure Copilot-generated content is appropriately marked. '
            $Result += 'Configure labels in the [Microsoft Purview compliance portal](https://compliance.microsoft.com/informationprotection) before deploying Copilot.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady013' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Tenant has sensitivity labels configured in Purview' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady013: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady013' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Tenant has sensitivity labels configured in Purview' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
