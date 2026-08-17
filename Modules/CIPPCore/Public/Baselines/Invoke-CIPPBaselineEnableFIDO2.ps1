function Invoke-CIPPBaselineEnableFIDO2 {
    <#
    .SYNOPSIS
        EnableFIDO2 executor: enables the FIDO2/passkey authentication method.
    .DESCRIPTION
        Graph now validates the WHOLE fido2 configuration on any write and requires
        keyRestrictions on every passkey profile - a tenant whose profiles predate that
        contract rejects even a plain state PATCH. So the write reads the live
        configuration, sets state=enabled and self-service allowed, gives any profile
        missing keyRestrictions the neutral block-nothing shape, and PATCHes the result
        back. Attestation: enforced on profile-less tenants (the classic's write), but
        when passkey profiles exist the top-level flag must AGREE with the default
        profile's attestationEnforcement or Graph rejects the whole write - so it is
        aligned, not forced. Only state is graded.
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
    $Config.isSelfServiceRegistrationAllowed = $true
    $PasskeyProfiles = @($Config.passkeyProfiles | Where-Object { $_ })
    if ($PasskeyProfiles.Count -gt 0) {
        # With passkey profiles present attestation is governed per-profile, and Graph
        # rejects a top-level flag that disagrees with the DEFAULT profile ("Attestation
        # enforcement cannot be enabled when it is disabled in default passkey profile").
        # The standard's deliverable is state=enabled - align the legacy flag with the
        # default profile instead of fighting a validation that cannot be won here.
        $DefaultProfile = @($PasskeyProfiles | Where-Object { "$($_.id)" -eq "$($Config.defaultPasskeyProfile)" }) | Select-Object -First 1
        $Config.isAttestationEnforced = "$(($DefaultProfile ?? $PasskeyProfiles[0]).attestationEnforcement)" -ne 'disabled'
    } else {
        $Config.isAttestationEnforced = $true
    }
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
