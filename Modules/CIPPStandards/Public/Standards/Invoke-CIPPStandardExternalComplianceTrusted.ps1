function Invoke-CIPPStandardExternalComplianceTrusted {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ExternalComplianceTrusted
    .SYNOPSIS
        (Label) Sets the Cross-tenant access setting to trust external compliant devices
    .DESCRIPTION
        (Helptext) Sets the state of the Cross-tenant access setting to trust external compliant devices. This allows guest users to use a compliant device from their home tenant to access your tenant.
        (DocsDescription) Sets the state of the Cross-tenant access setting to trust external compliant devices. This allows guest users to use a compliant device from their home tenant to access your tenant.
    .NOTES
        CAT
            Entra (AAD) Standards
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.ExternalComplianceTrusted.state","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-08-25
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyCrossTenantAccessPolicyDefault
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'ExternalComplianceTrusted' -TenantFilter $Tenant -Preset Entra

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    try {
        $ExternalComplianceTrusted = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default?$select=inboundTrust' -tenantid $Tenant)
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ExternalComplianceTrusted state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Get state value using null-coalescing operator
    $state = $Settings.state.value ?? $Settings.state
    $WantedState = if ($state -eq 'true') { $true } else { $false }
    $StateMessage = if ($WantedState) { 'enabled' } else { 'disabled' }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'ExternalComplianceTrusted: Invalid state parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($ExternalComplianceTrusted.inboundTrust.isCompliantDeviceAccepted -eq $WantedState ) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External Compliance Trusted is already $StateMessage." -sev Info
        } else {
            try {
                $NewBody = $ExternalComplianceTrusted
                $NewBody.inboundTrust.isCompliantDeviceAccepted = $WantedState
                $NewBody = ConvertTo-Json -Depth 10 -InputObject $NewBody -Compress
                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -Type patch -Body $NewBody -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Set External Compliance Trusted to $StateMessage." -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set External Compliance Trusted to $StateMessage. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            isCompliantDeviceAccepted = $ExternalComplianceTrusted.inboundTrust.isCompliantDeviceAccepted
        }
        $ExpectedValue = @{
            isCompliantDeviceAccepted = $WantedState
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.ExternalComplianceTrusted' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ExternalComplianceTrusted' -FieldValue $ExternalComplianceTrusted.inboundTrust.isCompliantDeviceAccepted -StoreAs bool -Tenant $Tenant
    }

    if ($Settings.alert -eq $true) {

        if ($ExternalComplianceTrusted.inboundTrust.isCompliantDeviceAccepted -eq $WantedState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External Compliance Trusted is $StateMessage." -sev Info
        } else {
            Write-StandardsAlert -message "External Compliance Trusted is not $StateMessage" -object $ExternalComplianceTrusted.inboundTrust -tenant $Tenant -standardName 'ExternalComplianceTrusted' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "External Compliance Trusted is not $StateMessage." -sev Info
        }
    }
}
