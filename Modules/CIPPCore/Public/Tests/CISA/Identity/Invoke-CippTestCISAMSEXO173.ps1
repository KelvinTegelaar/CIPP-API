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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoAdminAuditLogConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Audit logs SHALL be maintained for at least 1 year' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO173' -TenantFilter $Tenant
            return
        }

        $AuditConfigObject = $AuditConfig | Select-Object -First 1

        if ($AuditConfigObject.AdminAuditLogEnabled -eq $true) {
            $Result = "✅ **Pass**: Admin audit log is enabled (provides 1 year retention).`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- AdminAuditLogEnabled: $($AuditConfigObject.AdminAuditLogEnabled)"
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: Admin audit log is not enabled.`n`n"
            $Result += "**Current Settings:**`n"
            $Result += "- AdminAuditLogEnabled: $($AuditConfigObject.AdminAuditLogEnabled)"
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO173' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Audit logs SHALL be maintained for at least 1 year' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Audit logs SHALL be maintained for at least 1 year' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO173' -TenantFilter $Tenant
    }
}
