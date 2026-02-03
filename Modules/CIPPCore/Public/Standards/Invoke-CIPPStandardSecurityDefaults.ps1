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
            "CISA (MS.AAD.11.1v1)"
        EXECUTIVETEXT
            Activates Microsoft's baseline security configuration that requires multi-factor authentication and blocks legacy authentication methods. This provides essential security protection for organizations without complex conditional access policies, significantly improving security posture with minimal configuration.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Security Defaults state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {

        if ($SecureDefaultsState.IsEnabled -ne $true) {
            try {
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
            Write-StandardsAlert -message 'Security Defaults is not enabled' -object ($SecureDefaultsState | Select-Object displayName, isEnabled, description) -tenant $tenant -standardName 'SecurityDefaults' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SecurityDefaults' -FieldValue $SecureDefaultsState.IsEnabled -StoreAs bool -Tenant $tenant
        $CurrentData = @{
            SecurityDefaultsEnabled = $SecureDefaultsState.IsEnabled
        }
        $ExpectedData = @{
            SecurityDefaultsEnabled = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SecurityDefaults' -CurrentValue $CurrentData -ExpectedValue $ExpectedData -Tenant $tenant
    }
}
