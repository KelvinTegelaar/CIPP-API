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
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableSMS'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/SMS' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    If ($Settings.remediate -eq $true) {
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
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableSMS' -FieldValue $StateIsCorrect -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableSMS' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
