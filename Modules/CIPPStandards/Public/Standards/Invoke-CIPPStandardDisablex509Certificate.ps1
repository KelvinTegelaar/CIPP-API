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
        EXECUTIVETEXT
            Disables certificate-based authentication as a multi-factor authentication method, typically used when organizations want to standardize on other authentication methods or when certificate management becomes too complex for the security benefit provided.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-18
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/x509Certificate' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the Disablex509Certificate state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is already disabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'x509Certificate' -Enabled $false
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is not enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'x509Certificate authentication method is enabled' -object $CurrentState -tenant $tenant -standardName 'Disablex509Certificate' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            Disablex509Certificate = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            Disablex509Certificate = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.Disablex509Certificate' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'Disablex509Certificate' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
