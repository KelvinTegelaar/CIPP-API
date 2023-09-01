param($tenant)

$DehydratedTenant = (New-ExoRequest -tenantid $Tenant -cmdlet "Get-OrganizationConfig").IsDehydrated
if ($DehydratedTenant) {
    New-ExoRequest -tenantid $Tenant -cmdlet "Enable-OrganizationCustomization"
}
    
try {

    $AuditLogEnabled = (New-ExoRequest -tenantid $Tenant -cmdlet "Get-AdminAuditLogConfig").UnifiedAuditLogIngestionEnabled
    if ($AuditLogEnabled) {
        Write-LogMessage -API "Standards" -tenant $tenant -message "Unified Audit Log already enabled." -sev Info
    }
    else {
        $AdminAuditLogParams = @{
            UnifiedAuditLogIngestionEnabled = $true
        }
        New-ExoRequest -tenantid $Tenant -cmdlet "Set-AdminAuditLogConfig" -cmdParams $AdminAuditLogParams
        Write-LogMessage -API "Standards" -tenant $tenant -message "Unified Audit Log Enabled." -sev Info
    }

}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to apply Unified Audit Log. Error: $ErrorMessage" -sev Error
}