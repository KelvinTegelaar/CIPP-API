function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    TAP
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Enables TAP and sets the default TAP lifetime to 1 hour. This configuration also allows you to select is a TAP is single use or multi-logon.
    .DOCSDESCRIPTION
    Enables Temporary Password generation for the tenant.
    .ADDEDCOMPONENT
    {"type":"Select","label":"Select TAP Lifetime","name":"standards.TAP.config","values":[{"label":"Only Once","value":"true"},{"label":"Multiple Logons","value":"false"}]}
    .LABEL
    Enable Temporary Access Passwords
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Enables TAP and sets the default TAP lifetime to 1 hour. This configuration also allows you to select is a TAP is single use or multi-logon.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.config) -or $Settings.config -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'TAP: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'TemporaryAccessPass' -Enabled $true -TAPisUsableOnce $Settings.config
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is not enabled.' -sev Alert
        }
    }
}




