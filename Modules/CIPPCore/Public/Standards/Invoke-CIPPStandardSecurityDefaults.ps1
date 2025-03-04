function Invoke-CIPPStandardSecurityDefaults {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SecurityDefaults
    .SYNOPSIS
        (Label) Enable Security Defaults
    .DESCRIPTION
        (Helptext) Enables security defaults for the tenant, for newer tenants this is enabled by default. Do not enable this feature if you use Conditional Access.
        (DocsDescription) Enables SD for the tenant, which disables all forms of basic authentication and enforces users to configure MFA. Users are only prompted for MFA when a logon is considered 'suspect' by Microsoft.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2021-11-19
        POWERSHELLEQUIVALENT
            [Read more here](https://www.cyberdrain.com/automating-with-powershell-enabling-secure-defaults-and-sd-explained/)
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'SecurityDefaults'

    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)

    If ($Settings.remediate -eq $true) {

        if ($SecureDefaultsState.IsEnabled -ne $true) {
            try {
                Write-Host "Secure Defaults is disabled. Enabling for $tenant" -ForegroundColor Yellow
                $body = '{ "isEnabled": true }'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -Type patch -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Security Defaults.' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Security Defaults. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is already enabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($SecureDefaultsState.IsEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SecurityDefaults' -FieldValue $SecureDefaultsState.IsEnabled -StoreAs bool -Tenant $tenant
    }
}
