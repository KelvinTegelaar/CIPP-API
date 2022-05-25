param($tenant)

try {
    $AdminAuditLogParams = @{
        SendFromAliasEnabled = $true
    }
    New-ExoRequest -tenantid $Tenant -cmdlet "Set-OrganizationConfig" -cmdParams $AdminAuditLogParams
    Log-request -API "Standards" -tenant $tenant -message "Send from alias Enabled." -sev Info

}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Failed to apply Send from Alias Standard. Error: $($_.exception.message)" -sev Error
}