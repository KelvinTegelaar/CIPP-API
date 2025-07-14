function Invoke-CIPPStandardAuthMethodsPolicyMigration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AuthMethodsPolicyMigration
    .SYNOPSIS
        (Label) Complete Authentication Methods Policy Migration
    .DESCRIPTION
        (Helptext) Completes the migration of authentication methods policy to the new format
        (DocsDescription) Sets the authentication methods policy migration state to complete. This is required when migrating from legacy authentication policies to the new unified authentication methods policy.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-01-08
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.policyMigrationState -eq 'migrationComplete') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration is already complete.' -sev Info
        } else {
            try {
                New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant -body '{"policyMigrationState": "migrationComplete"}' -type PATCH
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration completed successfully.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to complete authentication methods policy migration: $($_.Exception.Message)" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.policyMigrationState -ne 'migrationComplete') {
            Write-StandardsAlert -message 'Authentication methods policy migration is not complete. Please check if you have legacy SSPR settings or MFA settings set: https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-authentication-methods-manage' -object $CurrentInfo -tenant $tenant -standardName 'AuthMethodsPolicyMigration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration is not complete' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $migrationComplete = $CurrentInfo.policyMigrationState -eq 'migrationComplete'
        Set-CIPPStandardsCompareField -FieldName 'standards.AuthMethodsPolicyMigration' -FieldValue $migrationComplete -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AuthMethodsPolicyMigration' -FieldValue $migrationComplete -StoreAs bool -Tenant $tenant
    }

}
