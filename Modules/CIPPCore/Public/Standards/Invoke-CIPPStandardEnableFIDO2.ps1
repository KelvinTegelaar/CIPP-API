function Invoke-CIPPStandardEnableFIDO2 {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableFIDO2
    .SYNOPSIS
        (Label) Enable FIDO2 capabilities
    .DESCRIPTION
        (Helptext) Enables the FIDO2 authenticationMethod for the tenant
        (DocsDescription) Enables FIDO2 capabilities for the tenant. This allows users to use FIDO2 keys like a Yubikey for authentication.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2022-12-08
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableFIDO2'

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -tenantid $Tenant
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableFIDO2 state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'enabled')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is already enabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Fido2' -Enabled $true
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is enabled' -sev Info
        } else {
            Write-StandardsAlert -message "FIDO2 Support is not enabled" -object $CurrentState -tenant $tenant -standardName 'EnableFIDO2' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect ? $true : $CurrentState
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableFIDO2' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'EnableFIDO2' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
