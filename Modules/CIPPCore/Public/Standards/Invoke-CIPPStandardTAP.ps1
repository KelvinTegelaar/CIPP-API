function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) TAP
    .SYNOPSIS
        (Label) Enable Temporary Access Passwords
    .DESCRIPTION
        (Helptext) Enables TAP and sets the default TAP lifetime to 1 hour. This configuration also allows you to select if a TAP is single use or multi-logon.
        (DocsDescription) Enables Temporary Password generation for the tenant.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select TAP Lifetime","name":"standards.TAP.config","options":[{"label":"Only Once","value":"true"},{"label":"Multiple Logons","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2022-03-15
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'TAP'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant

    # Get config value using null-coalescing operator
    $config = $Settings.config.value ?? $Settings.config
    if ($null -eq $config) { $config = $True }

    $StateIsCorrect = ($CurrentState.state -eq 'enabled') -and
                        ([System.Convert]::ToBoolean($CurrentState.isUsableOnce) -eq [System.Convert]::ToBoolean($config))

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Passwords is already enabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $Tenant -APIName 'Standards' -AuthenticationMethodId 'TemporaryAccessPass' -Enabled $true -TAPisUsableOnce $config
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Passwords is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Temporary Access Passwords is not enabled.' -sev Alert
        }
    }
}
