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
        $AuditConfig = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAdminAuditLogConfig'

        if (-not $AuditConfig) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Microsoft Purview Audit logging SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO171' -TenantFilter $Tenant
            return
        }

        $AuditConfigObject = $AuditConfig | Select-Object -First 1

        if ($AuditConfigObject.UnifiedAuditLogIngestionEnabled -eq $true) {
            $Result = [System.Text.StringBuilder]::new("✅ **Pass**: Microsoft Purview Audit (Standard) logging is enabled.`n`n")
            $null = $Result.Append("**Current Settings:**`n")
            $null = $Result.Append("- UnifiedAuditLogIngestionEnabled: $($AuditConfigObject.UnifiedAuditLogIngestionEnabled)")
            $Status = 'Passed'
        } else {
            $Result = [System.Text.StringBuilder]::new("❌ **Fail**: Microsoft Purview Audit (Standard) logging is not enabled.`n`n")
            $null = $Result.Append("**Current Settings:**`n")
            $null = $Result.Append("- UnifiedAuditLogIngestionEnabled: $($AuditConfigObject.UnifiedAuditLogIngestionEnabled)")
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO171' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Microsoft Purview Audit logging SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Microsoft Purview Audit logging SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO171' -TenantFilter $Tenant
    }
}
