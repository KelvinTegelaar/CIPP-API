function Invoke-CIPPStandardFIDO2PasskeyProfiles {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) FIDO2PasskeyProfiles
    .SYNOPSIS
        (Label) Configure FIDO2 Passkey Profile
    .DESCRIPTION
        (Helptext) Configures the default FIDO2 passkey profile including AAGUID allowlists, attestation enforcement, and passkey types for the tenant.
        (DocsDescription) Manages the default FIDO2 passkey profile on the tenant authentication methods policy. Controls which authenticators (hardware keys, password managers, Microsoft Authenticator) are permitted via AAGUID allowlists, whether attestation is enforced, and which passkey types (device-bound, synced, or both) are allowed. This enables MSPs to centrally deploy phishing-resistant MFA configurations across tenants.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Configures the default passkey (FIDO2) profile that controls which authenticators users can register for phishing-resistant MFA. Supports allowlisting specific hardware keys (e.g., YubiKey models), password managers (e.g., 1Password), and Microsoft Authenticator by AAGUID, with control over attestation enforcement and passkey types.
        ADDEDCOMPONENT
            [{"type":"select","multiple":false,"name":"standards.FIDO2PasskeyProfiles.PasskeyTypes","label":"Allowed Passkey Types","options":[{"label":"Device-bound only","value":"deviceBound"},{"label":"Synced only","value":"synced"},{"label":"Both device-bound and synced","value":"deviceBound,synced"}],"required":true},{"type":"select","multiple":false,"name":"standards.FIDO2PasskeyProfiles.AttestationEnforcement","label":"Attestation Enforcement","options":[{"label":"Disabled (required for synced passkeys)","value":"disabled"},{"label":"Registration only","value":"registrationOnly"}],"required":true},{"type":"switch","name":"standards.FIDO2PasskeyProfiles.EnforceKeyRestrictions","label":"Enforce AAGUID Key Restrictions"},{"type":"select","multiple":false,"name":"standards.FIDO2PasskeyProfiles.EnforcementType","label":"Key Restriction Type","options":[{"label":"Allow listed AAGUIDs only","value":"allow"},{"label":"Block listed AAGUIDs","value":"block"}],"required":false},{"type":"textField","name":"standards.FIDO2PasskeyProfiles.AAGUIDs","label":"AAGUIDs (comma-separated list of authenticator AAGUIDs)","required":false}]
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-05-25
        POWERSHELLEQUIVALENT
            Graph API PATCH /policies/authenticationMethodsPolicy/authenticationMethodConfigurations/fido2
        RECOMMENDEDBY
            "CIPP"
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $PasskeyTypes = $Settings.PasskeyTypes.value ?? $Settings.PasskeyTypes

    $AttestationEnforcement = $Settings.AttestationEnforcement.value ?? $Settings.AttestationEnforcement


    $EnforceKeyRestrictions = [bool]$Settings.EnforceKeyRestrictions
    $EnforcementType = $Settings.EnforcementType.value ?? $Settings.EnforcementType ?? 'allow'

    # Parse AAGUIDs from comma-separated string
    $AAGUIDs = @()
    if (-not [string]::IsNullOrWhiteSpace($Settings.AAGUIDs)) {
        $AAGUIDs = @($Settings.AAGUIDs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    # Key restrictions require at least one AAGUID
    if ($EnforceKeyRestrictions -and $AAGUIDs.Count -eq 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'FIDO2PasskeyProfiles: Key restrictions are enabled but no AAGUIDs specified. Provide at least one AAGUID or disable key restrictions.' -sev Error
        return
    }

    # Get current FIDO2 configuration
    try {
        $CurrentConfig = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "FIDO2PasskeyProfiles: Could not retrieve current FIDO2 configuration. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $true
    }

    # Find the default passkey profile
    $DefaultProfileId = $CurrentConfig.defaultPasskeyProfile
    $DefaultProfile = $CurrentConfig.passkeyProfiles | Where-Object { $_.id -eq $DefaultProfileId }

    # Determine compliance against the default profile
    $StateIsCorrect = $false
    if ($DefaultProfile) {
        $ExistingAAGUIDs = @($DefaultProfile.keyRestrictions.aaGuids | Sort-Object)
        $DesiredAAGUIDs = @($AAGUIDs | Sort-Object)
        $AAGUIDsMatch = (-not (Compare-Object -ReferenceObject $DesiredAAGUIDs -DifferenceObject $ExistingAAGUIDs -ErrorAction SilentlyContinue))

        $StateIsCorrect = (
            $DefaultProfile.passkeyTypes -eq $PasskeyTypes -and
            $DefaultProfile.attestationEnforcement -eq $AttestationEnforcement -and
            $DefaultProfile.keyRestrictions.isEnforced -eq $EnforceKeyRestrictions -and
            $DefaultProfile.keyRestrictions.enforcementType -eq $EnforcementType -and
            $AAGUIDsMatch
        )
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'FIDO2PasskeyProfiles: Default passkey profile is already configured correctly.' -sev Info
        } else {
            try {
                # Update the default profile in the profiles array, preserve all others
                $ExistingProfiles = @($CurrentConfig.passkeyProfiles)
                $UpdatedProfiles = foreach ($Profile in $ExistingProfiles) {
                    if ($Profile.id -eq $DefaultProfileId) {
                        @{
                            id                     = $Profile.id
                            name                   = $Profile.name
                            passkeyTypes           = $PasskeyTypes
                            attestationEnforcement = $AttestationEnforcement
                            keyRestrictions        = @{
                                isEnforced      = $EnforceKeyRestrictions
                                enforcementType = $EnforcementType
                                aaGuids         = $AAGUIDs
                            }
                        }
                    } else {
                        $Profile
                    }
                }

                $Body = @{
                    '@odata.type'   = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
                    passkeyProfiles = @($UpdatedProfiles)
                } | ConvertTo-Json -Compress -Depth 10

                Write-Host "FIDO2PasskeyProfiles: Request body: $Body"

                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -Type PATCH -Body $Body -ContentType 'application/json' -AsApp $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "FIDO2PasskeyProfiles: Successfully configured default passkey profile with $($AAGUIDs.Count) AAGUID(s), passkey types '$PasskeyTypes', attestation '$AttestationEnforcement'." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "FIDO2PasskeyProfiles: Failed to configure default passkey profile. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'FIDO2PasskeyProfiles: Default passkey profile is compliant.' -sev Info
        } else {
            $AlertDetails = if ($DefaultProfile) {
                'Default passkey profile exists but is not configured as expected.'
            } else {
                'No default passkey profile found.'
            }
            Write-StandardsAlert -message "FIDO2PasskeyProfiles: $AlertDetails" -object $DefaultProfile -tenant $Tenant -standardName 'FIDO2PasskeyProfiles' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            PasskeyTypes           = $DefaultProfile.passkeyTypes ?? 'N/A'
            AttestationEnforcement = $DefaultProfile.attestationEnforcement ?? 'N/A'
            EnforceKeyRestrictions = $DefaultProfile.keyRestrictions.isEnforced ?? $false
            EnforcementType        = $DefaultProfile.keyRestrictions.enforcementType ?? 'N/A'
            AAGUIDs                = ($DefaultProfile.keyRestrictions.aaGuids ?? @()) -join ', '
        }
        $ExpectedValue = [PSCustomObject]@{
            PasskeyTypes           = $PasskeyTypes
            AttestationEnforcement = $AttestationEnforcement
            EnforceKeyRestrictions = $EnforceKeyRestrictions
            EnforcementType        = $EnforcementType
            AAGUIDs                = $AAGUIDs -join ', '
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.FIDO2PasskeyProfiles' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'FIDO2PasskeyProfiles' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
