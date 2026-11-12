# Pester tests for Test-CIPPCAPolicyPhishingResistant and the Test-CIPPCAGapGuestExclusion roll-up.
#
#   - A strength counted as phishing-resistant as soon as ANY allowed combination held a
#     phishing-resistant method. The built-in "Multifactor authentication" strength allows FIDO2 next
#     to password + push, so it qualified, and the persona matrix showed admins as covered.
#   - The "guests face no multifactor requirement" roll-up was suppressed by any All-users MFA
#     policy, including the one that exempts guests.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Test-CIPPCAPolicyPhishingResistant', 'Test-CIPPCAGapGuestExclusion', 'New-CIPPCAGapFinding') {
        $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $FunctionPath) { throw "Could not locate $Name.ps1 under Modules/" }
        . $FunctionPath
    }

    $script:Reference = Get-Content (Join-Path $RepoRoot 'Config/SecuritySimulations/CAAnalysis/Reference.json') -Raw | ConvertFrom-Json -Depth 20
    $script:BuiltInMfa = '00000000-0000-0000-0000-000000000002'
    $script:BuiltInPhishingResistant = '00000000-0000-0000-0000-000000000004'

    function New-Context {
        param([object[]]$Policies = @(), [hashtable]$AuthStrengths = @{})
        @{
            Policies      = @($Policies)
            Enabled       = @($Policies | Where-Object { $_.state -eq 'enabled' })
            AuthStrengths = $AuthStrengths
            Data          = @{ Reference = $script:Reference }
        }
    }

    function New-StrengthPolicy {
        param([string]$Name = 'Require strength', $Strength)
        [pscustomobject]@{ id = [guid]::NewGuid().ToString(); displayName = $Name; state = 'enabled'; grantControls = [pscustomobject]@{ builtInControls = @(); authenticationStrength = $Strength } }
    }

    function New-MfaPolicy {
        param([string]$Name, [string[]]$IncludeUsers = @('All'), [string[]]$ExcludeUsers = @(), $ExcludeGuests, $IncludeGuests, [string[]]$Controls = @('mfa'))
        [pscustomobject]@{
            id            = [guid]::NewGuid().ToString()
            displayName   = $Name
            state         = 'enabled'
            conditions    = [pscustomobject]@{
                users        = [pscustomobject]@{ includeUsers = $IncludeUsers; excludeUsers = $ExcludeUsers; excludeGuestsOrExternalUsers = $ExcludeGuests; includeGuestsOrExternalUsers = $IncludeGuests }
                applications = [pscustomobject]@{ includeApplications = @('All') }
            }
            grantControls = [pscustomobject]@{ builtInControls = $Controls }
        }
    }

    function Get-RollUp { param($Findings) @($Findings | Where-Object { $_.title -like '*face no multifactor requirement*' }) }
}

Describe 'Test-CIPPCAPolicyPhishingResistant' {
    It 'does not count the built-in Multifactor authentication strength, which also allows FIDO2' {
        $Strength = [pscustomobject]@{ id = $script:BuiltInMfa; displayName = 'Multifactor authentication' }
        $Catalog = @{ $script:BuiltInMfa = [pscustomobject]@{ id = $script:BuiltInMfa; allowedCombinations = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor', 'password,microsoftAuthenticatorPush', 'password,sms') } }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Strength $Strength) -Context (New-Context -AuthStrengths $Catalog) | Should -BeFalse
    }

    It 'counts a custom strength whose every combination is phishing-resistant' {
        $Strength = [pscustomobject]@{ id = 'custom-1'; displayName = 'Admins' }
        $Catalog = @{ 'custom-1' = [pscustomobject]@{ id = 'custom-1'; allowedCombinations = @('fido2', 'windowsHelloForBusiness') } }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Strength $Strength) -Context (New-Context -AuthStrengths $Catalog) | Should -BeTrue
    }

    It 'reads the combinations from the policy when the strength is not in the catalog' {
        $Strength = [pscustomobject]@{ id = 'custom-2'; displayName = 'FIDO2 or TOTP'; allowedCombinations = @('fido2', 'password,hardwareOath') }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Strength $Strength) -Context (New-Context) | Should -BeFalse
    }

    It 'does not let a phishing-resistant sounding name override weaker combinations' {
        $Strength = [pscustomobject]@{ id = 'custom-3'; displayName = 'Phishing resistant (with push fallback)' }
        $Catalog = @{ 'custom-3' = [pscustomobject]@{ id = 'custom-3'; allowedCombinations = @('fido2', 'password,microsoftAuthenticatorPush') } }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Name 'Phishing-resistant MFA for admins' -Strength $Strength) -Context (New-Context -AuthStrengths $Catalog) | Should -BeFalse
    }

    It 'counts the built-in Phishing-resistant MFA strength by id' {
        $Strength = [pscustomobject]@{ id = $script:BuiltInPhishingResistant; displayName = 'Phishing-resistant MFA' }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Strength $Strength) -Context (New-Context) | Should -BeTrue
    }

    It 'falls back to the strength name only when the combinations are unknown' {
        $Strength = [pscustomobject]@{ id = 'custom-4'; displayName = 'FIDO2 only' }

        Test-CIPPCAPolicyPhishingResistant -Policy (New-StrengthPolicy -Strength $Strength) -Context (New-Context) | Should -BeTrue
    }

    It 'is false for a policy without an authentication strength, whatever its name' {
        $Policy = [pscustomobject]@{ displayName = 'Phishing-resistant MFA for admins'; grantControls = [pscustomobject]@{ builtInControls = @('mfa') } }

        Test-CIPPCAPolicyPhishingResistant -Policy $Policy -Context (New-Context) | Should -BeFalse
    }
}

Describe 'Test-CIPPCAGapGuestExclusion roll-up' {
    It 'fires when the only MFA policy is the one that exempts all guests' {
        $Policy = New-MfaPolicy -Name 'MFA for all users' -ExcludeUsers @('GuestsOrExternalUsers')

        $RollUp = Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies @($Policy)))

        $RollUp.Count | Should -Be 1
        $RollUp[0].severity | Should -Be 'High'
    }

    It 'fires when the exemption lists every guest type in the structured block' {
        $AllTypes = [pscustomobject]@{ guestOrExternalUserTypes = (@($script:Reference.guestTypeOrder) -join ','); externalTenants = [pscustomobject]@{ membershipKind = 'all' } }
        $Policy = New-MfaPolicy -Name 'MFA for all users' -ExcludeGuests $AllTypes

        (Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies @($Policy)))).Count | Should -Be 1
    }

    It 'stays quiet when every guest type is exempt but only for enumerated external organizations' {
        $Enumerated = [pscustomobject]@{ guestOrExternalUserTypes = (@($script:Reference.guestTypeOrder) -join ','); externalTenants = [pscustomobject]@{ membershipKind = 'enumerated'; members = @('11111111-1111-1111-1111-111111111111') } }
        $Policy = New-MfaPolicy -Name 'MFA for all users' -ExcludeGuests $Enumerated

        (Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies @($Policy)))).Count | Should -Be 0
    }

    It 'stays quiet when another All-users MFA policy does not exempt guests' {
        $Policies = @(
            (New-MfaPolicy -Name 'Block legacy auth' -ExcludeUsers @('GuestsOrExternalUsers') -Controls @('block')),
            (New-MfaPolicy -Name 'MFA for everyone')
        )

        (Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies $Policies))).Count | Should -Be 0
    }

    It 'stays quiet when a guest-specific MFA policy exists' {
        $Policies = @(
            (New-MfaPolicy -Name 'MFA for all users' -ExcludeUsers @('GuestsOrExternalUsers')),
            (New-MfaPolicy -Name 'MFA for guests' -IncludeUsers @('GuestsOrExternalUsers'))
        )

        (Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies $Policies))).Count | Should -Be 0
    }

    It 'stays quiet when the MFA policy exempts only some guest types' {
        $SomeTypes = [pscustomobject]@{ guestOrExternalUserTypes = 'serviceProvider'; externalTenants = [pscustomobject]@{ membershipKind = 'all' } }
        $Policy = New-MfaPolicy -Name 'MFA for all users' -ExcludeGuests $SomeTypes

        (Get-RollUp (Test-CIPPCAGapGuestExclusion -Context (New-Context -Policies @($Policy)))).Count | Should -Be 0
    }
}
