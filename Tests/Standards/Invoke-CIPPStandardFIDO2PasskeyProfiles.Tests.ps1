# Pester tests for Invoke-CIPPStandardFIDO2PasskeyProfiles
#
# HubSpot 47469698699: AAGUIDs added to the passkey profile did not take effect. A profile's AAGUID
# allow/block list only applies while keyRestrictions.isEnforced = $true; sent with isEnforced = $false
# the list is stored but inert - the profile keeps no active restriction (confirmed live against Graph
# beta). The standard exposed the AAGUIDs field and the "Enforce AAGUID Key Restrictions" switch as
# independent inputs, so an operator who added AAGUIDs without toggling the switch got an unenforced,
# ineffective list. The remediation must now enforce key restrictions whenever AAGUIDs are supplied.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardFIDO2PasskeyProfiles.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardFIDO2PasskeyProfiles.ps1 under Modules/' }

    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp) $script:mockCurrentConfig }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $Uri, $Type, $Body, $ContentType, $AsApp) $script:lastBody = $Body }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData, $headers) $script:logs.Add(@{ Message = $message; Sev = $sev }) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AndroidAAGUID = 'de1e552d-db1d-4423-a619-566b625cdc84'
    $script:OperatorAAGUID = '11111111-1111-1111-1111-111111111111'

    # A tenant with the Microsoft default profile (no restrictions) plus an operator-managed profile
    # that already carries an AAGUID - the remediation must resend the operator profile untouched.
    function script:New-MockConfig {
        [pscustomobject]@{
            '@odata.type'         = '#microsoft.graph.fido2AuthenticationMethodConfiguration'
            id                    = 'fido2'
            state                 = 'enabled'
            defaultPasskeyProfile = 'p-default'
            passkeyProfiles       = @(
                [pscustomobject]@{ id = 'p-default'; name = 'Microsoft default profile'; passkeyTypes = 'deviceBound'; attestationEnforcement = 'disabled'; keyRestrictions = [pscustomobject]@{ isEnforced = $false; enforcementType = 'block'; aaGuids = @() } }
                [pscustomobject]@{ id = 'p-custom'; name = 'Operator profile'; passkeyTypes = 'synced'; attestationEnforcement = 'registrationOnly'; keyRestrictions = [pscustomobject]@{ isEnforced = $true; enforcementType = 'allow'; aaGuids = @($script:OperatorAAGUID) } }
            )
        }
    }
}

Describe 'Invoke-CIPPStandardFIDO2PasskeyProfiles remediation' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:lastBody = $null
        $script:mockCurrentConfig = script:New-MockConfig
    }

    It 'enforces key restrictions when AAGUIDs are supplied even though the enforce switch is off' {
        # The core regression: without this, isEnforced was $false and Graph dropped the AAGUIDs.
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'deviceBound,synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $false
            EnforcementType        = 'allow'
            AAGUIDs                = $script:AndroidAAGUID
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        $script:lastBody | Should -Not -BeNullOrEmpty
        $body = $script:lastBody | ConvertFrom-Json
        $default = @($body.passkeyProfiles) | Where-Object { $_.id -eq 'p-default' }
        $default.keyRestrictions.isEnforced | Should -BeTrue
        @($default.keyRestrictions.aaGuids) | Should -Be @($script:AndroidAAGUID)
        $default.keyRestrictions.enforcementType | Should -Be 'allow'
    }

    It 'serializes a single AAGUID as a JSON array' {
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'deviceBound,synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $true
            EnforcementType        = 'allow'
            AAGUIDs                = $script:AndroidAAGUID
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        # Guards the classic ConvertTo-Json single-element unwrap: aaGuids must be [".."], not "..".
        $script:lastBody | Should -Match '"aaGuids":\['
    }

    It 'resends every other passkey profile untouched (the PATCH replaces the whole collection)' {
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'deviceBound,synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $true
            EnforcementType        = 'allow'
            AAGUIDs                = $script:AndroidAAGUID
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        $body = $script:lastBody | ConvertFrom-Json
        @($body.passkeyProfiles).Count | Should -Be 2
        $operator = @($body.passkeyProfiles) | Where-Object { $_.id -eq 'p-custom' }
        $operator | Should -Not -BeNullOrEmpty
        @($operator.keyRestrictions.aaGuids) | Should -Be @($script:OperatorAAGUID)
    }

    It 'preserves multiple supplied AAGUIDs on the default profile' {
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'deviceBound,synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $false
            EnforcementType        = 'allow'
            AAGUIDs                = "$script:AndroidAAGUID, 90a3ccdf-635c-4729-a248-9b709135078f"
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        $body = $script:lastBody | ConvertFrom-Json
        $default = @($body.passkeyProfiles) | Where-Object { $_.id -eq 'p-default' }
        @($default.keyRestrictions.aaGuids).Count | Should -Be 2
        @($default.keyRestrictions.aaGuids) | Should -Contain '90a3ccdf-635c-4729-a248-9b709135078f'
        $default.keyRestrictions.isEnforced | Should -BeTrue
    }

    It 'does not enforce or send AAGUIDs when none are supplied' {
        # passkeyTypes differs from the tenant so remediation still fires and we can inspect the body.
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $false
            EnforcementType        = 'allow'
            AAGUIDs                = ''
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        $body = $script:lastBody | ConvertFrom-Json
        $default = @($body.passkeyProfiles) | Where-Object { $_.id -eq 'p-default' }
        $default.keyRestrictions.isEnforced | Should -BeFalse
        @($default.keyRestrictions.aaGuids).Count | Should -Be 0
    }

    It 'refuses to enforce with no AAGUIDs and does not PATCH' {
        $Settings = @{
            remediate              = $true
            PasskeyTypes           = 'deviceBound,synced'
            AttestationEnforcement = 'disabled'
            EnforceKeyRestrictions = $true
            EnforcementType        = 'allow'
            AAGUIDs                = ''
        }

        Invoke-CIPPStandardFIDO2PasskeyProfiles -Tenant $script:Tenant -Settings $Settings

        $script:lastBody | Should -BeNullOrEmpty
        @($script:logs | Where-Object { $_.Sev -eq 'Error' }).Count | Should -Be 1
    }
}
