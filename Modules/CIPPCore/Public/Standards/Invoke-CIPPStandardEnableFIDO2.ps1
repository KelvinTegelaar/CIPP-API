function Invoke-CIPPStandardEnableFIDO2 {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    EnableFIDO2
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Enables the FIDO2 authenticationMethod for the tenant
    .DOCSDESCRIPTION
    Enables FIDO2 capabilities for the tenant. This allows users to use FIDO2 keys like a Yubikey for authentication.
    .ADDEDCOMPONENT
    .LABEL
    Enable FIDO2 capabilities
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Enables the FIDO2 authenticationMethod for the tenant
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Fido2' -Enabled $true
        }
    }


    if ($Settings.alert -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'EnableFIDO2' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}




