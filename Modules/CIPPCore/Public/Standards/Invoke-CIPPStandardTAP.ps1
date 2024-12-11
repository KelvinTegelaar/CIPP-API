function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TAP
    .SYNOPSIS
        (Label) Enable Temporary Access Passwords
    .DESCRIPTION
        (Helptext) Enables TAP and sets the default TAP lifetime to 1 hour. This configuration also allows you to select is a TAP is single use or multi-logon.
        (DocsDescription) Enables Temporary Password generation for the tenant.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
            {"type":"Select","label":"Select TAP Lifetime","name":"standards.TAP.config","values":[{"label":"Only Once","value":"true"},{"label":"Multiple Logons","value":"false"}]}
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TAP'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant
    if ($null -eq $Settings.config) { $Settings.config = $True }
    $StateIsCorrect =   ($CurrentState.state -eq 'enabled') -and
                        ([System.Convert]::ToBoolean($CurrentState.isUsableOnce) -eq [System.Convert]::ToBoolean($Settings.config))

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'TemporaryAccessPass' -Enabled $true -TAPisUsableOnce $Settings.config
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is not enabled.' -sev Alert
        }
    }
}
