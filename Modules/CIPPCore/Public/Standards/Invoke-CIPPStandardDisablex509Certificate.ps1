function Invoke-CIPPStandardDisablex509Certificate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) Disablex509Certificate
    .SYNOPSIS
        (Label) Disables Certificates as an MFA method
    .DESCRIPTION
        (Helptext) This blocks users from using Certificates as an MFA method.
        (DocsDescription) This blocks users from using Certificates as an MFA method.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "highimpact"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'Disablex509Certificate'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/x509Certificate' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'x509Certificate' -Enabled $false
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'Disablex509Certificate' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}
