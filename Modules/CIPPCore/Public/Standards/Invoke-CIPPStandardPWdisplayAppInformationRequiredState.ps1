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
            "CIS M365 5.0 (2.3.1)"
            "EIDSCA.AM03"
            "EIDSCA.AM04"
            "EIDSCA.AM06"
            "EIDSCA.AM07"
            "EIDSCA.AM09"
            "EIDSCA.AM10"
            "NIST CSF 2.0 (PR.AA-03)"
        EXECUTIVETEXT
            Enhances authentication security by requiring users to match numbers and showing detailed information about login requests, including application names and location data. This helps employees verify legitimate login attempts and prevents unauthorized access through more secure authentication methods.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the PWdisplayAppInformationRequiredState state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

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
        $CurrentValue = @{
            state                              = $CurrentState.state
            numberMatchingRequiredState        = $CurrentState.featureSettings.numberMatchingRequiredState.state
            displayAppInformationRequiredState = $CurrentState.featureSettings.displayAppInformationRequiredState.state
        }
        $ExpectedValue = @{
            state                              = 'enabled'
            numberMatchingRequiredState        = 'enabled'
            displayAppInformationRequiredState = 'enabled'
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PWdisplayAppInformationRequiredState' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
    }
}
