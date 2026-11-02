# Certificate auth must only be enabled once the stored SAM certificate has proven it can obtain a token.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function Get-GraphTokenFromCert { param($TenantId, $AppId, $Scope, $Certificate, [switch]$SkipCache) }
    function Update-CIPPSAMCertificateEnvCache { param($Name, $PfxBase64) }
    function Get-NormalizedError { param($message) "normalized: $message" }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSAMCertificateAuth.ps1')
}

Describe 'Test-CIPPSAMCertificateAuth' {
    BeforeEach {
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'CERT'; Thumbprint = 'ABC123'; PfxBase64 = 'PFX' } }
        Mock Get-GraphTokenFromCert { @{ access_token = 'token' } }
        Mock Update-CIPPSAMCertificateEnvCache {}
    }

    It 'succeeds and refreshes the process certificate cache when a token is issued' {
        $Result = Test-CIPPSAMCertificateAuth -ApplicationId 'app' -TenantId 'tenant'

        $Result.Success | Should -BeTrue
        $Result.Thumbprint | Should -Be 'ABC123'
        $Result.Error | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPSAMCertificate -Times 1 -Exactly -ParameterFilter { $SkipCache }
        Should -Invoke Get-GraphTokenFromCert -Times 1 -Exactly -ParameterFilter { $AppId -eq 'app' -and $TenantId -eq 'tenant' -and $SkipCache }
        Should -Invoke Update-CIPPSAMCertificateEnvCache -Times 1 -Exactly -ParameterFilter { $Name -eq 'SAMCertificate' -and $PfxBase64 -eq 'PFX' }
    }

    It 'reports failure without throwing when the token request fails' {
        Mock Get-GraphTokenFromCert { throw 'AADSTS700027: Client assertion contains an invalid signature.' }

        $Result = Test-CIPPSAMCertificateAuth -ApplicationId 'app' -TenantId 'tenant'

        $Result.Success | Should -BeFalse
        $Result.Thumbprint | Should -Be 'ABC123'
        $Result.Error | Should -BeLike '*AADSTS700027*'
        Should -Invoke Update-CIPPSAMCertificateEnvCache -Times 0 -Exactly
    }

    It 'reports failure when the token response has no access token' {
        Mock Get-GraphTokenFromCert { $null }

        $Result = Test-CIPPSAMCertificateAuth -ApplicationId 'app' -TenantId 'tenant'

        $Result.Success | Should -BeFalse
    }

    It 'reports failure when no certificate is stored' {
        Mock Get-CIPPSAMCertificate { $null }

        $Result = Test-CIPPSAMCertificateAuth -ApplicationId 'app' -TenantId 'tenant'

        $Result.Success | Should -BeFalse
        $Result.Error | Should -Be 'No SAM certificate is stored.'
        Should -Invoke Get-GraphTokenFromCert -Times 0 -Exactly
    }
}
