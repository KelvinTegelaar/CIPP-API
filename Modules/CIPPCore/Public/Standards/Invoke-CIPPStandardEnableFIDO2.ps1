function Invoke-CIPPStandardEnableFIDO2 {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate) {
        

        try {
            $body = '{"@odata.type":"#microsoft.graph.fido2AuthenticationMethodConfiguration","id":"Fido2","includeTargets":[{"id":"all_users","isRegistrationRequired":false,"targetType":"group","displayName":"All users"}],"excludeTargets":[],"isAttestationEnforced":true,"isSelfServiceRegistrationAllowed":true,"keyRestrictions":{"aaGuids":[],"enforcementType":"block","isEnforced":false},"state":"enabled"}'
            New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -Type patch -Body $body -ContentType 'application/json'
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled FIDO2 Support' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable FIDO2 Support: $($_.exception.message)" -sev Error
        }
    }
        
    if ($Settings.alert) {

        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -tenantid $Tenant
        if ($CurrentInfo.state -eq 'enabled') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is not enabled' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'EnableFIDO2' -FieldValue [bool]$CurrentInfo.state -StoreAs bool -Tenant $tenant
    }
}
