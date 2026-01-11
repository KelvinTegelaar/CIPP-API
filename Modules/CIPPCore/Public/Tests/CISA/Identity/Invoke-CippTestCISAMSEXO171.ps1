function Invoke-CippTestCISAMSEXO171 {
    <#
    .SYNOPSIS
    Tests MS.EXO.17.1 - Microsoft Purview Audit (Standard) logging SHALL be enabled

    .DESCRIPTION
    Checks if unified audit log ingestion is enabled

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $AuditConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAdminAuditLogConfig'

        if (-not $AuditConfig) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO171' -TenantFilter $Tenant
            return
        }

        $AuditConfigObject = $AuditConfig | Select-Object -First 1

        if ($AuditConfigObject.UnifiedAuditLogIngestionEnabled -eq $true) {
            $Result = "✅ **Pass**: Microsoft Purview Audit (Standard) logging is enabled.`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- UnifiedAuditLogIngestionEnabled: $($AuditConfigObject.UnifiedAuditLogIngestionEnabled)"
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: Microsoft Purview Audit (Standard) logging is not enabled.`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- UnifiedAuditLogIngestionEnabled: $($AuditConfigObject.UnifiedAuditLogIngestionEnabled)"
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO171' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO171' -TenantFilter $Tenant
    }
}
