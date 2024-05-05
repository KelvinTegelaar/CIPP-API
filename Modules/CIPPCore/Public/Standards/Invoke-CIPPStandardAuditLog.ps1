function Invoke-CIPPStandardAuditLog {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    Write-Host ($Settings | ConvertTo-Json)
    $AuditLogEnabled = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AdminAuditLogConfig' -Select UnifiedAuditLogIngestionEnabled).UnifiedAuditLogIngestionEnabled

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        $DehydratedTenant = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -Select IsDehydrated).IsDehydrated
        if ($DehydratedTenant) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Enable-OrganizationCustomization'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Organization customization enabled.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable organization customization. Error: $ErrorMessage" -sev Debug
            }
        }

        try {
            if ($AuditLogEnabled) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log already enabled.' -sev Info
            } else {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-AdminAuditLogConfig' -cmdParams @{UnifiedAuditLogIngestionEnabled = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log Enabled.' -sev Info
            }

        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Unified Audit Log. Error: $ErrorMessage" -sev Error
        }
    }
    if ($Settings.alert -eq $true) {

        if ($AuditLogEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log is not enabled' -sev Alert
        }
    }
    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'AuditLog' -FieldValue $AuditLogEnabled -StoreAs bool -Tenant $tenant
    }
}
