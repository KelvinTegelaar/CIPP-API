function Invoke-CIPPStandardDisableVoice {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableVoice
    .SYNOPSIS
        (Label) Disables Voice call as an MFA method
    .DESCRIPTION
        (Helptext) This blocks users from using Voice call as an MFA method. If a user only has Voice as a MFA method, they will be unable to log in.
        (DocsDescription) Disables Voice call as an MFA method for the tenant. If a user only has Voice call as a MFA method, they will be unable to sign in.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 5.0 (2.3.5)"
            "EIDSCA.AV01"
            "NIST CSF 2.0 (PR.AA-03)"
        EXECUTIVETEXT
            Disables voice call authentication due to security vulnerabilities and social engineering risks. This forces users to adopt more secure authentication methods like authenticator apps, improving overall account security by eliminating phone-based attack vectors.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-18
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Voice' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableVoice state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is already disabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Voice' -Enabled $false
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is not enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Voice authentication method is enabled' -object $CurrentState -tenant $tenant -standardName 'DisableVoice' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            DisableVoice = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableVoice = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableVoice' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableVoice' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
