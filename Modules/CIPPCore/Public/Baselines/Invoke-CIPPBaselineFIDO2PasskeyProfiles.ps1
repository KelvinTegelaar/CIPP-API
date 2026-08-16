function Invoke-CIPPBaselineFIDO2PasskeyProfiles {
    <#
    .SYNOPSIS
        FIDO2PasskeyProfiles executor: rewrites the default passkey profile.
    .DESCRIPTION
        Rebuilds the profile ARRAY with only the default profile changed - every other
        profile resends untouched, because the PATCH replaces the whole collection and
        dropping one would delete it. The classic's exact write, app-only as the classic
        wrote it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $DefaultId = "$($Current.defaultProfileId)"
    if ([string]::IsNullOrWhiteSpace($DefaultId)) { throw 'The tenant reports no default passkey profile - refusing a blind profile rewrite.' }

    $PasskeyTypes = "$($Remediate.passkeyTypes)"
    $Attestation = "$($Remediate.attestationEnforcement)"
    $Enforce = [bool]($Remediate.enforceKeyRestrictions -eq $true -or "$($Remediate.enforceKeyRestrictions)" -eq 'True')
    $EnforcementType = "$($Remediate.enforcementType)"
    if ([string]::IsNullOrWhiteSpace($EnforcementType)) { $EnforcementType = 'allow' }
    $AAGUIDs = @("$($Remediate.aaGuids)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $UpdatedProfiles = @(@($Current.allProfiles) | ForEach-Object {
            if ("$($_.id)" -eq $DefaultId) {
                @{
                    id                     = "$($_.id)"
                    name                   = "$($_.name)"
                    passkeyTypes           = $PasskeyTypes
                    attestationEnforcement = $Attestation
                    keyRestrictions        = @{
                        isEnforced      = $Enforce
                        enforcementType = $EnforcementType
                        aaGuids         = @($AAGUIDs)
                    }
                }
            } else { $_ }
        })

    $Body = @{
        '@odata.type'   = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
        passkeyProfiles = @($UpdatedProfiles)
    } | ConvertTo-Json -Compress -Depth 10
    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -type PATCH -body $Body -AsApp $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated the default passkey profile ($PasskeyTypes, attestation $Attestation, restrictions $Enforce)." -Sev 'Info'
}
