function Invoke-CIPPStandardDisableVoice {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableVoice
    .CAT
    Entra (AAD) Standards
    .TAG
    "highimpact"
    .HELPTEXT
    This blocks users from using Voice call as an MFA method. If a user only has Voice as a MFA method, they will be unable to log in.
    .DOCSDESCRIPTION
    Disables Voice call as an MFA method for the tenant. If a user only has Voice call as a MFA method, they will be unable to sign in.
    .ADDEDCOMPONENT
    .LABEL
    Disables Voice call as an MFA method
    .IMPACT
    High Impact
    .DOCSDESCRIPTION
    This blocks users from using Voice call as an MFA method. If a user only has Voice as a MFA method, they will be unable to log in.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Voice' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Voice' -Enabled $false
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Voice authentication method is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableVoice' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}




