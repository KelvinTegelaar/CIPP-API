function Invoke-CippTestCyberIns_13 {
    <#
    .SYNOPSIS
    Cyber Insurance Q13 - Logs are collected centrally
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_13'; TestType = 'Identity'; Risk = 'Medium'; Name = 'Logs are collected centrally'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Cyber Insurance' }

    try {
        $AuditConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAdminAuditLogConfig')[0]
        if (-not $AuditConfig) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No audit log configuration found for this tenant. Sync the report data first.'
            return
        }

        $UnifiedAuditLog = $AuditConfig.UnifiedAuditLogIngestionEnabled -eq $true
        $OrgConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig')[0]
        $MailboxAuditing = if (-not $OrgConfig) { 'Unknown' } elseif ($OrgConfig.AuditDisabled -eq $true) { 'Off' } else { 'On' }

        $Result = "Unified audit log: **$(if ($UnifiedAuditLog) { 'On' } else { 'Off' })**. Mailbox auditing: **$MailboxAuditing**.`n`nHow long logs are kept, and whether a SIEM or SOC monitors them, is not visible here and needs an MSP attestation."

        $Status = if (-not $UnifiedAuditLog) { 'Failed' } elseif ($MailboxAuditing -eq 'On') { 'Passed' } else { 'Investigate' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_13: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
