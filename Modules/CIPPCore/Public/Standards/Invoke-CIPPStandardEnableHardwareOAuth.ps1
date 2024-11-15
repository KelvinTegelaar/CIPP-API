function Invoke-CIPPStandardEnableHardwareOAuth {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableHardwareOAuth
    .SYNOPSIS
        (Label) Enable Hardware OAuth tokens
    .DESCRIPTION
        (Helptext) Enables the HardwareOath authenticationMethod for the tenant. This allows you to use hardware tokens for generating 6 digit MFA codes.
        (DocsDescription) Enables Hardware OAuth tokens for the tenant. This allows users to use hardware tokens like a Yubikey for authentication.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableHardwareOAuth'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/HardwareOath' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.state -eq 'enabled')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'HardwareOath' -Enabled $true
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'EnableHardwareOAuth' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
