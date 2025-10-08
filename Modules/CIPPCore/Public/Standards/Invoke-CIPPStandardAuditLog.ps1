function Invoke-CIPPStandardAuditLog {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AuditLog
    .SYNOPSIS
        (Label) Enable the Unified Audit Log
    .DESCRIPTION
        (Helptext) Enables the Unified Audit Log for tracking and auditing activities. Also runs Enable-OrganizationCustomization if necessary.
        (DocsDescription) Enables the Unified Audit Log for tracking and auditing activities. Also runs Enable-OrganizationCustomization if necessary.
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS M365 5.0 (3.1.1)"
            "mip_search_auditlog"
            "NIST CSF 2.0 (DE.CM-09)"
        EXECUTIVETEXT
            Activates comprehensive activity logging across Microsoft 365 services to track user actions, system changes, and security events. This provides essential audit trails for compliance requirements, security investigations, and regulatory reporting.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Enable-OrganizationCustomization
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'AuditLog' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'AuditLog'

    Write-Host ($Settings | ConvertTo-Json)
    $AuditLogEnabled = [bool](New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AdminAuditLogConfig' -Select UnifiedAuditLogIngestionEnabled).UnifiedAuditLogIngestionEnabled

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        $DehydratedTenant = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -Select IsDehydrated).IsDehydrated
        if ($DehydratedTenant -eq $true) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Enable-OrganizationCustomization'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Organization customization enabled.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable organization customization. Error: $ErrorMessage" -sev Debug
            }
        }

        try {
            if ($AuditLogEnabled -eq $true) {
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

        if ($AuditLogEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Unified Audit Log is not enabled' -object @{AuditLogEnabled = $AuditLogEnabled } -tenant $Tenant -standardName 'AuditLog' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Unified Audit Log is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $AuditLogEnabled -eq $true ? $true : $AuditLogEnabled
        Set-CIPPStandardsCompareField -FieldName 'standards.AuditLog' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'AuditLog' -FieldValue $AuditLogEnabled -StoreAs bool -Tenant $tenant
    }
}
