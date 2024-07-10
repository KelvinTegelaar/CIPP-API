function Invoke-CIPPStandardPWdisplayAppInformationRequiredState {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    PWdisplayAppInformationRequiredState
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    "CIS"
    .HELPTEXT
    Enables the MS authenticator app to display information about the app that is requesting authentication. This displays the application name.
    .DOCSDESCRIPTION
    Allows users to use Passwordless with Number Matching and adds location information from the last request
    .ADDEDCOMPONENT
    .LABEL
    Enable Passwordless with Location information and Number Matching
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Enables the MS authenticator app to display information about the app that is requesting authentication. This displays the application name.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'PWdisplayAppInformationRequiredState' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}




