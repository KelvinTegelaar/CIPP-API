function Invoke-CIPPStandardDisableEmail {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableEmail
    .SYNOPSIS
        (Label) Disables Email as an MFA method
    .DESCRIPTION
        (Helptext) This blocks users from using email as an MFA method. This disables the email OTP option for guest users, and instead prompts them to create a Microsoft account.
        (DocsDescription) This blocks users from using email as an MFA method. This disables the email OTP option for guest users, and instead prompts them to create a Microsoft account.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-18
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableEmail'

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Email' -tenantid $Tenant
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableEmail state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is already disabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Email' -Enabled $false
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is not enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Email authentication method is enabled' -object $CurrentState -tenant $tenant -standardName 'DisableEmail' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect -eq $true ? $true :  $CurrentState
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableEmail' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableEmail' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
