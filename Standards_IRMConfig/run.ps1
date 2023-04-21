param($tenant)

try {
    $DehydratedTenant = (New-ExoRequest -tenantid $Tenant -cmdlet "Get-OrganizationConfig").IsDehydrated
    if ($DehydratedTenant) {
        New-ExoRequest -tenantid $Tenant -cmdlet "Enable-OrganizationCustomization"
    }
    $AdminAuditLogParams = @{
        UnifiedAuditLogIngestionEnabled = $true
    }
	New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-IRMConfiguration" -cmdParams @{SimplfiedClientAccessEnabled = true; EnablPdfEncryption = $true; DecrytAttachmentForEncryptOnly = $true;JournlReportDecryptionEnabled = $true}
    Write-LogMessage -API "Standards" -tenant $tenant -message "Setting IRM CONFIG" -sev Info


}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to set IRM CONFIG. Error: $ErrorMessage" -sev Error
}