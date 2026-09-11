function Invoke-CippTestORCA124 {
    <#
    .SYNOPSIS
    Safe attachments unknown malware response set to block messages
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeAttachmentPolicies'

        if (-not $Policies) {
            if (-not (Test-CIPPStandardLicense -StandardName 'ORCA124' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in the database. Data collection for this tenant may not have completed yet - refresh the cache and try again.' -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            }
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.Action -in @('Block', 'Quarantine')) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All Safe Attachments policies have unknown malware response set to Block.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) Safe Attachments policies do not have unknown malware response set to Block.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Action |`n")
            $null = $Result.Append("|------------|--------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.Action) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA124' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe attachments unknown malware response set to block messages' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
