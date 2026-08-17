function Invoke-CIPPBaselineEnableFIDO2 {
    <#
    .SYNOPSIS
        EnableFIDO2 executor: enables the FIDO2/passkey authentication method.
    .DESCRIPTION
        Graph now validates the WHOLE fido2 configuration on any write and requires
        keyRestrictions on every passkey profile - a tenant whose profiles predate that
        contract rejects even a plain state PATCH. So the write reads the live
        configuration, sets the state (attestation enforced, self-service allowed - the
        declarative spec's values), gives any profile missing keyRestrictions the neutral
        block-nothing shape, and PATCHes the result back.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Uri = 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Fido2'
    $Config = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true
    $Config.state = 'enabled'
    $Config.isAttestationEnforced = $true
    $Config.isSelfServiceRegistrationAllowed = $true
    foreach ($PasskeyProfile in @($Config.passkeyProfiles)) {
        if (-not $PasskeyProfile) { continue }
        if (-not $PasskeyProfile.keyRestrictions) {
            # Neutral: restrictions not enforced, nothing blocked.
            $PasskeyProfile | Add-Member -NotePropertyName 'keyRestrictions' -NotePropertyValue ([PSCustomObject]@{
                    isEnforced = $false; enforcementType = 'block'; aaGuids = @()
                }) -Force
        }
    }
    $Body = ConvertTo-Json -Depth 20 -Compress -InputObject ($Config | Select-Object -Property * -ExcludeProperty '@odata.context')
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -type PATCH -body $Body -AsApp $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Enabled the FIDO2 authentication method (passkey profiles normalized).' -Sev 'Info'
}
