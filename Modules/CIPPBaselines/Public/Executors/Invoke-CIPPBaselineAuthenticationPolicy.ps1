function Invoke-CIPPBaselineAuthenticationPolicy {
    <#
    .SYNOPSIS
        AuthenticationPolicy executor: splats the spec's params into Set-CIPPAuthenticationPolicy.
    .DESCRIPTION
        Set-CIPPAuthenticationPolicy reads the method's live configuration and changes only the
        requested fields, so several standards can each own one sub-setting of a method without
        resetting each other (a Graph PATCH replaces complex properties wholesale). When the
        spec omits Enabled the method's current state is kept.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Params = @{ Tenant = $TenantFilter; APIName = 'Baselines' }
    foreach ($Property in ($Remediate.params ?? [PSCustomObject]@{}).PSObject.Properties) {
        $Params[$Property.Name] = $Property.Value
    }
    # Enabled is mandatory on the helper and also writes the method's state; keep the live one.
    if (-not $Params.ContainsKey('Enabled')) {
        $Live = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/$($Params.AuthenticationMethodId)" -tenantid $TenantFilter -AsApp $true
        $Params.Enabled = "$($Live.state)" -eq 'enabled'
    }
    $null = Set-CIPPAuthenticationPolicy @Params
}
