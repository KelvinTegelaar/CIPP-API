function Invoke-CIPPStandardDisableQRCodePin {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableQRCodePin
    .SYNOPSIS
        (Label) Disables QR Code Pin as an MFA method
    .DESCRIPTION
        (Helptext) This blocks users from using QR Code Pin as an MFA method. If a user only has QR Code Pin as a MFA method, they will be unable to log in.
        (DocsDescription) Disables QR Code Pin as an MFA method for the tenant. If a user only has QR Code Pin as a MFA method, they will be unable to sign in.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Disables QR Code Pin authentication method due to security concerns, forcing users to adopt more secure authentication alternatives. This helps standardize authentication methods and reduces potential security vulnerabilities while ensuring employees use more robust multi-factor authentication options.
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2024-02-10
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/QRCodePin' -tenantid $Tenant
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableQRCodePin state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.state -eq 'disabled')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'QR Code Pin authentication method is already disabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'QRCodePin' -Enabled $false
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'QR Code Pin authentication method is not enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'QR Code Pin authentication method is enabled' -object $CurrentState -tenant $tenant -standardName 'DisableQRCodePin' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'QR Code Pin authentication method is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $StateIsCorrect -eq $true ? $true :  $CurrentState

        $CurrentValue = [PSCustomObject]@{
            DisableQRCodePin = $state
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableQRCodePin = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableQRCodePin' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableQRCodePin' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
