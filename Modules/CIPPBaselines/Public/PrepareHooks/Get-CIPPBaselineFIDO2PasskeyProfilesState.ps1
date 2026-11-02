function Get-CIPPBaselineFIDO2PasskeyProfilesState {
    <#
    .SYNOPSIS
        Prepare hook for FIDO2PasskeyProfiles: the default passkey profile's settings.
    .DESCRIPTION
        Grades the DEFAULT passkey profile only - other profiles are operator-managed and
        never touched, which is also why the executor rebuilds the profile array preserving
        them. Graded: passkey types, attestation enforcement, whether key restrictions are
        enforced, their enforcement type, and the sorted AAGUID set.

        Enforcing key restrictions with no AAGUIDs would lock every authenticator out (allow
        mode) or restrict nothing (block mode) - the classic refused the combination, and it
        reports No Data here.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Config = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Fido2Configuration' -CollectorType 'AuthenticationMethodsPolicy') | Select-Object -First 1
    if (-not $Config) { return @{ Current = $null } }

    $V = $Item.Variables
    $PasskeyTypes = "$($V.PasskeyTypes.value ?? $V.PasskeyTypes)"
    $Attestation = "$($V.AttestationEnforcement.value ?? $V.AttestationEnforcement)"
    if ([string]::IsNullOrWhiteSpace($PasskeyTypes) -or [string]::IsNullOrWhiteSpace($Attestation)) { return @{ Current = $null } }
    $EnforceRestrictions = [bool]($V.EnforceKeyRestrictions -eq $true)
    $EnforcementType = "$($V.EnforcementType.value ?? $V.EnforcementType)"
    if ([string]::IsNullOrWhiteSpace($EnforcementType)) { $EnforcementType = 'allow' }
    $AAGUIDs = @(@($V.AAGUIDs) | ForEach-Object { "$($_.value ?? $_)" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    # The list only takes effect while isEnforced = $true, so supplying AAGUIDs implies enforcement.
    if ($AAGUIDs.Count -gt 0) { $EnforceRestrictions = $true }
    # Windows Hello and Authenticator passkeys stay allowed unless the operator opts out.
    if ($EnforceRestrictions -and $EnforcementType -eq 'allow' -and "$($V.AllowMicrosoftPasskeys)" -ne 'False') {
        $AAGUIDs = @($AAGUIDs; '08987058-cadc-4b81-b6e1-30de50dcbe96', '9ddd1817-af5a-4672-a2b9-3e3dd95000a9', '6028b017-b1d4-4c02-b4b3-afcdafc96bb2', 'de1e552d-db1d-4423-a619-566b625cdc84', '90a3ccdf-635c-4729-a248-9b709135078f')
    }
    $AAGUIDs = @($AAGUIDs | Sort-Object -Unique)
    if ($EnforceRestrictions -and $AAGUIDs.Count -eq 0) { return @{ Current = $null } }

    $DefaultProfile = @($Config.passkeyProfiles) | Where-Object { "$($_.id)" -eq "$($Config.defaultPasskeyProfile)" } | Select-Object -First 1

    $Current = if ($DefaultProfile) {
        [PSCustomObject]@{
            passkeyTypes            = "$($DefaultProfile.passkeyTypes)"
            attestationEnforcement  = "$($DefaultProfile.attestationEnforcement)"
            keyRestrictionsEnforced = [bool]$DefaultProfile.keyRestrictions.isEnforced
            enforcementType         = "$($DefaultProfile.keyRestrictions.enforcementType)"
            aaGuids                 = @($DefaultProfile.keyRestrictions.aaGuids | Sort-Object)
        }
    } else {
        # No default profile at all: everything grades against empties, so the row shows
        # exactly which facts a remediation would establish.
        [PSCustomObject]@{ passkeyTypes = ''; attestationEnforcement = ''; keyRestrictionsEnforced = $false; enforcementType = ''; aaGuids = @() }
    }
    # Carried for the executor: the PATCH must resend the whole profile array.
    $Current | Add-Member -NotePropertyName 'allProfiles' -NotePropertyValue @($Config.passkeyProfiles)
    $Current | Add-Member -NotePropertyName 'defaultProfileId' -NotePropertyValue "$($Config.defaultPasskeyProfile)"

    @{
        Expected = [PSCustomObject]@{
            passkeyTypes            = $PasskeyTypes
            attestationEnforcement  = $Attestation
            keyRestrictionsEnforced = $EnforceRestrictions
            enforcementType         = $EnforcementType
            aaGuids                 = @($AAGUIDs)
        }
        Current  = $Current
    }
}
