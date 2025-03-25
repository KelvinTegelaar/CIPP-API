function Invoke-CIPPStandardPWdisplayAppInformationRequiredState {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PWdisplayAppInformationRequiredState
    .SYNOPSIS
        (Label) Enable Passwordless with Location information and Number Matching
    .DESCRIPTION
        (Helptext) Enables the MS authenticator app to display information about the app that is requesting authentication. This displays the application name.
        (DocsDescription) Allows users to use Passwordless with Number Matching and adds location information from the last request
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.state -eq 'enabled') -and
    ($CurrentState.featureSettings.numberMatchingRequiredState.state -eq 'enabled') -and
    ($CurrentState.featureSettings.displayAppInformationRequiredState.state -eq 'enabled')

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is already enabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Passwordless with Information and Number Matching is not enabled' -object $CurrentState -tenant $tenant -standardName 'PWdisplayAppInformationRequiredState' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'PWdisplayAppInformationRequiredState' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PWdisplayAppInformationRequiredState' -FieldValue $FieldValue -Tenant $tenant
    }
}
