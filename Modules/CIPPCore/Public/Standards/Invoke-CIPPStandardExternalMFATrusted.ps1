function Invoke-CIPPStandardExternalMFATrusted {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ExternalMFATrusted
    .SYNOPSIS
        (Label) Sets the Cross-tenant access setting to trust external MFA
    .DESCRIPTION
        (Helptext) Sets the state of the Cross-tenant access setting to trust external MFA. This allows guest users to use their home tenant MFA to access your tenant.
        (DocsDescription) Sets the state of the Cross-tenant access setting to trust external MFA. This allows guest users to use their home tenant MFA to access your tenant.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.ExternalMFATrusted.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-26
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyCrossTenantAccessPolicyDefault
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ExternalMFATrusted'

    $ExternalMFATrusted = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $Tenant)

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state
    $WantedState = if ($state -eq 'true') { $true } else { $false }
    $StateMessage = if ($WantedState) { 'enabled' } else { 'disabled' }



    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'ExternalMFATrusted: Invalid state parameter set' -sev Error
        Return
    }

    if ($Settings.remediate -eq $true) {

        Write-Host 'Remediate External MFA Trusted'
        if ($ExternalMFATrusted.inboundTrust.isMfaAccepted -eq $WantedState ) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External MFA Trusted is already $StateMessage." -sev Info
        } else {
            try {
                $NewBody = $ExternalMFATrusted
                $NewBody.inboundTrust.isMfaAccepted = $WantedState
                $NewBody = ConvertTo-Json -Depth 10 -InputObject $NewBody -Compress
                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -Type patch -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set External MFA Trusted to $StateMessage." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set External MFA Trusted to $StateMessage. Error: $ErrorMessage" -sev Error
            }
        }
    }
    if ($Settings.report -eq $true) {
        $state = $ExternalMFATrusted.inboundTrust.isMfaAccepted ? $true : $ExternalMFATrusted.inboundTrust
        Set-CIPPStandardsCompareField -FieldName 'standards.ExternalMFATrusted' -FieldValue $ExternalMFATrusted.inboundTrust.isMfaAccepted -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ExternalMFATrusted' -FieldValue $ExternalMFATrusted.inboundTrust.isMfaAccepted -StoreAs bool -Tenant $Tenant
    }

    if ($Settings.alert -eq $true) {

        if ($ExternalMFATrusted.inboundTrust.isMfaAccepted -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External MFA Trusted is $StateMessage." -sev Info
        } else {
            Write-StandardsAlert -message "External MFA Trusted is not $StateMessage" -object $ExternalMFATrusted.inboundTrust -tenant $Tenant -standardName 'ExternalMFATrusted' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External MFA Trusted is not $StateMessage." -sev Info
        }
    }
}
