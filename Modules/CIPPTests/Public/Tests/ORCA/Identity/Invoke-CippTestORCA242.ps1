function Invoke-CippTestORCA242 {
    <#
    .SYNOPSIS
    Important protection alerts enabled
    #>
    param($Tenant)

    try {
        # This test would check for alert policies related to ATP/Defender for Office 365
        # Since we don't have an alert policy cache, we'll provide informational guidance

        $Status = 'Informational'
        $Result = "Alert policies for protection features should be enabled and monitored.`n`n"
        $Result += "**Recommended Alert Policies:**`n`n"
        $Result += "- Messages reported by users as malware or phish`n"
        $Result += "- Email sending limit exceeded`n"
        $Result += "- Suspicious email forwarding activity`n"
        $Result += "- Malware campaign detected`n"
        $Result += "- Suspicious connector activity`n"
        $Result += "- Unusual external user file activity`n"
        $Result += "`n**Action Required:** Verify alert policies are configured in Microsoft 365 Security & Compliance Center"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA242' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Important protection alerts enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA242' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Important protection alerts enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Configuration'
    }
}
