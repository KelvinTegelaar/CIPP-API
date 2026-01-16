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
        EXECUTIVETEXT
            Allows external partners and vendors to use their own organization's multi-factor authentication when accessing company resources, streamlining collaboration while maintaining security standards. This reduces friction for external users while ensuring they still meet authentication requirements.
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

    try {
        $ExternalMFATrusted = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $Tenant)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ExternalMFATrusted state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state
    $WantedState = if ($state -eq 'true') { $true } else { $false }
    $StateMessage = if ($WantedState) { 'enabled' } else { 'disabled' }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'ExternalMFATrusted: Invalid state parameter set' -sev Error
        return
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
        $CurrentValue = @{
            isMfaAccepted = $ExternalMFATrusted.inboundTrust.isMfaAccepted
        }
        $ExpectedValue = @{
            isMfaAccepted = $WantedState
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.ExternalMFATrusted' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
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
