function Invoke-CIPPStandardExternalMFATrusted {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $ExternalMFATrusted = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $Tenant)
    $WantedState = if ($Settings.state -eq 'true') { $true } else { $false }
    $StateMessage = if ($WantedState) { 'enabled' } else { 'disabled' }

    if ($Settings.remediate) {

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
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to set External MFA Trusted to $StateMessage. Error: $($_.exception.message)" -sev Error
            }
        }
    }

    if ($Settings.alert) {

        if ($ExternalMFATrusted.inboundTrust.isMfaAccepted -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "External MFA Trusted is $StateMessage." -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "External MFA Trusted is not $StateMessage." -sev Alert
        }

    }

    if ($Settings.report) {

        Add-CIPPBPAField -FieldName 'ExternalMFATrusted' -FieldValue [bool]$ExternalMFATrusted.inboundTrust.isMfaAccepted -StoreAs bool -Tenant $tenant
    }
}