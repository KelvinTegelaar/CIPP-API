function Invoke-CIPPStandardExternalMFATrusted {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    ExternalMFATrusted
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Sets the state of the Cross-tenant access setting to trust external MFA. This allows guest users to use their home tenant MFA to access your tenant.
    .ADDEDCOMPONENT
    {"type":"Select","label":"Select value","name":"standards.ExternalMFATrusted.state","values":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
    .LABEL
    Sets the Cross-tenant access setting to trust external MFA
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyCrossTenantAccessPolicyDefault
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets the state of the Cross-tenant access setting to trust external MFA. This allows guest users to use their home tenant MFA to access your tenant.
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $ExternalMFATrusted = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $Tenant)
    $WantedState = if ($Settings.state -eq 'true') { $true } else { $false }
    $StateMessage = if ($WantedState) { 'enabled' } else { 'disabled' }

    if ($Settings.report -eq $true) {

        Add-CIPPBPAField -FieldName 'ExternalMFATrusted' -FieldValue $ExternalMFATrusted.inboundTrust.isMfaAccepted -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'ExternalMFATrusted: Invalid state parameter set' -sev Error
        Return
    }

    if ($Settings.remediate -eq $true) {

        Write-Host 'Remediate External MFA Trusted'
        if ($ExternalMFATrusted.inboundTrust.isMfaAccepted -eq $WantedState ) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "External MFA Trusted is already $StateMessage." -sev Info
        } else {
            try {
                $NewBody = $ExternalMFATrusted
                $NewBody.inboundTrust.isMfaAccepted = $WantedState
                $NewBody = ConvertTo-Json -Depth 10 -InputObject $NewBody -Compress
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -Type patch -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Set External MFA Trusted to $StateMessage." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set External MFA Trusted to $StateMessage. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($ExternalMFATrusted.inboundTrust.isMfaAccepted -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "External MFA Trusted is $StateMessage." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "External MFA Trusted is not $StateMessage." -sev Alert
        }
    }
}




