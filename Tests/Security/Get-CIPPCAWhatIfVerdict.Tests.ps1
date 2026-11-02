BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/SecuritySimulations/Get-CIPPCAWhatIfVerdict.ps1')

    function Get-StrengthPolicy([string]$Id, [string[]]$Combinations) {
        [PSCustomObject]@{
            displayName   = "Strength $Id"
            state         = 'enabled'
            policyApplies = $true
            grantControls = [PSCustomObject]@{
                operator               = 'OR'
                builtInControls        = @()
                authenticationStrength = [PSCustomObject]@{ id = $Id; allowedCombinations = $Combinations }
            }
        }
    }
}

Describe 'Get-CIPPCAWhatIfVerdict authentication strength' {
    It 'treats the built-in Multifactor authentication strength as MFA an attacker with MFA satisfies' {
        $Policy = Get-StrengthPolicy '00000000-0000-0000-0000-000000000002' @('fido2', 'windowsHelloForBusiness', 'password,microsoftAuthenticatorPush', 'password,sms')
        $Verdict = Get-CIPPCAWhatIfVerdict -Policies @($Policy) -AttackerCanSatisfy @('mfa')
        $Verdict.verdict | Should -Be 'allowed'
        $Verdict.detail | Should -Be 'grantSatisfied'
        $Verdict.requiredControls | Should -Be @('mfa')
    }

    It 'still stops an attacker without MFA' {
        $Policy = Get-StrengthPolicy '00000000-0000-0000-0000-000000000002' @('password,microsoftAuthenticatorPush')
        (Get-CIPPCAWhatIfVerdict -Policies @($Policy) -AttackerCanSatisfy @()).detail | Should -Be 'challenged'
    }

    It 'stops an attacker with MFA when every allowed combination is phishing-resistant' {
        foreach ($Policy in @(
                (Get-StrengthPolicy '00000000-0000-0000-0000-000000000004' @()),
                (Get-StrengthPolicy 'b1f2c3d4-0000-4000-8000-000000000001' @('fido2', 'windowsHelloForBusiness', 'x509CertificateMultiFactor')))) {
            $Verdict = Get-CIPPCAWhatIfVerdict -Policies @($Policy) -AttackerCanSatisfy @('mfa') -Expected 'phishingResistant'
            $Verdict.detail | Should -Be 'challenged'
            $Verdict.meetsExpectation | Should -BeTrue
        }
    }
}
