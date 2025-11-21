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
        EXECUTIVETEXT
            Completes the transition from legacy authentication policies to Microsoft's modern unified authentication methods policy, ensuring the organization benefits from the latest security features and management capabilities. This migration enables enhanced security controls and simplified policy management.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-07-07
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicy
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the AuthMethodsPolicyMigration state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return
    }

    if ($null -eq $CurrentInfo) {
        throw 'Failed to retrieve current authentication methods policy information'
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.policyMigrationState -eq 'migrationComplete' -or $null -eq $CurrentInfo.policyMigrationState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration is already complete.' -sev Info
        } else {
            try {
                New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant -body '{"policyMigrationState": "migrationComplete"}' -type PATCH
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration completed successfully.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to complete authentication methods policy migration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.policyMigrationState -ne 'migrationComplete' -and $null -ne $CurrentInfo.policyMigrationState) {
            Write-StandardsAlert -message 'Authentication methods policy migration is not complete. Please check if you have legacy SSPR settings or MFA settings set: https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-authentication-methods-manage' -object $CurrentInfo -tenant $tenant -standardName 'AuthMethodsPolicyMigration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Authentication methods policy migration is not complete' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $migrationComplete = $CurrentInfo.policyMigrationState -eq 'migrationComplete' -or $null -eq $CurrentInfo.policyMigrationState
        Set-CIPPStandardsCompareField -FieldName 'standards.AuthMethodsPolicyMigration' -FieldValue $migrationComplete -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AuthMethodsPolicyMigration' -FieldValue $migrationComplete -StoreAs bool -Tenant $tenant
    }

}
