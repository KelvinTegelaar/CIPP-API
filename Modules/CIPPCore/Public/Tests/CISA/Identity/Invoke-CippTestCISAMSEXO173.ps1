function Invoke-CippTestCISAMSEXO173 {
    <#
    .SYNOPSIS
    Tests MS.EXO.17.3 - Audit logs SHALL be maintained for at least the minimum duration

    .DESCRIPTION
    Checks if admin audit log is enabled (provides 1 year retention)

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO173' -TenantFilter $Tenant
            return
        }

        $AuditConfigObject = $AuditConfig | Select-Object -First 1

        if ($AuditConfigObject.AdminAuditLogEnabled -eq $true) {
            $Result = "✅ **Pass**: Admin audit log is enabled (provides 1 year retention).`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- AdminAuditLogEnabled: $($AuditConfigObject.AdminAuditLogEnabled)"
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: Admin audit log is not enabled.`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- AdminAuditLogEnabled: $($AuditConfigObject.AdminAuditLogEnabled)"
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO173' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO173' -TenantFilter $Tenant
    }
}
