function Invoke-CIPPStandardDisableSMS {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableSMS
    .SYNOPSIS
        (Label) Disables SMS as an MFA method
    .DESCRIPTION
        (Helptext) This blocks users from using SMS as an MFA method. If a user only has SMS as a MFA method, they will be unable to log in.
        (DocsDescription) Disables SMS as an MFA method for the tenant. If a user only has SMS as a MFA method, they will be unable to sign in.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 5.0 (2.3.5)"
            "EIDSCA.AS04"
            "NIST CSF 2.0 (PR.AA-03)"
        EXECUTIVETEXT
            Disables SMS text messages as a multi-factor authentication method due to security vulnerabilities like SIM swapping attacks. This forces users to adopt more secure authentication methods like authenticator apps or hardware tokens, significantly improving account security.
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
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/SMS' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableSMS state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is already disabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'SMS' -Enabled $false
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is not enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'SMS authentication method is enabled' -object $CurrentState -tenant $tenant -standardName 'DisableSMS' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {

        $CurrentValue = [PSCustomObject]@{
            DisableSMS = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableSMS = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableSMS' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableSMS' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
