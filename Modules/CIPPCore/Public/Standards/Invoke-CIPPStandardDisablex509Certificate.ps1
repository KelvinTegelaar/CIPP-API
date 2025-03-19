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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'Disablex509Certificate'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/x509Certificate' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    If ($Settings.remediate -eq $true) {
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
        $state = $StateIsCorrect ? $true : $CurrentState
        Set-CIPPStandardsCompareField -FieldName 'standards.Disablex509Certificate' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'Disablex509Certificate' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
