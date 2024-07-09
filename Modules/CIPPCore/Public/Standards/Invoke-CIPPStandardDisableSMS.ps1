function Invoke-CIPPStandardDisableSMS {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableSMS
    .CAT
    Entra (AAD) Standards
    .TAG
    "highimpact"
    .HELPTEXT
    This blocks users from using SMS as an MFA method. If a user only has SMS as a MFA method, they will be unable to log in.
    .DOCSDESCRIPTION
    Disables SMS as an MFA method for the tenant. If a user only has SMS as a MFA method, they will be unable to sign in.
    .ADDEDCOMPONENT
    .LABEL
    Disables SMS as an MFA method
    .IMPACT
    High Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    This blocks users from using SMS as an MFA method. If a user only has SMS as a MFA method, they will be unable to log in.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/SMS' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'SMS' -Enabled $false
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'SMS authentication method is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableSMS' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}




