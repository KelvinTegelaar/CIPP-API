function Invoke-CippTestCIS_3_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (3.1.1) - Microsoft 365 audit log search SHALL be enabled
    #>
    param($Tenant)

    try {
        $Audit = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAdminAuditLogConfig'

        if (-not $Audit) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Microsoft 365 audit log search is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
            return
        }

        $Cfg = $Audit | Select-Object -First 1

        if ($Cfg.UnifiedAuditLogIngestionEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Unified Audit Log ingestion is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Unified Audit Log ingestion is disabled (UnifiedAuditLogIngestionEnabled: $($Cfg.UnifiedAuditLogIngestionEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Microsoft 365 audit log search is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Microsoft 365 audit log search is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    }
}
