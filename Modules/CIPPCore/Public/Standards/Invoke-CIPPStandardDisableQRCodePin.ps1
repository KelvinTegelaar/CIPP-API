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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/QRCodePin' -tenantid $Tenant
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
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableQRCodePin' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableQRCodePin' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
