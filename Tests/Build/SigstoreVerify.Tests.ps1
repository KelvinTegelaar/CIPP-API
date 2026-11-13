# Pester tests for CIPP.SigstoreVerify in CIPPSharp.
#
# A real build-provenance bundle from the dev channel must verify against the pinned Sigstore
# public-good chain, and each class of tampering must fail at its own stage.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Dll = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    if (-not (Test-Path $Dll)) { throw "CIPPSharp.dll not built at $Dll" }
    if (-not ('CIPP.SigstoreVerify' -as [type])) { Add-Type -Path $Dll }

    $Fixtures = Join-Path $RepoRoot 'Tests/Fixtures/ContainerAttestation'
    $script:BundleJson = Get-Content -Raw (Join-Path $Fixtures 'dev-fa58a723.bundle.json')
    $script:Chain = Get-Content -Raw (Join-Path $RepoRoot 'Config/sigstore-public-good-chain.pem')
    $script:Digest = 'fa58a723252622a45841f2cb9f0a9f8025569775d97be84f573311992584472c'

    function Edit-Bundle([scriptblock]$Change) {
        $Bundle = $script:BundleJson | ConvertFrom-Json -Depth 20
        & $Change $Bundle
        $Bundle | ConvertTo-Json -Depth 20 -Compress
    }

    function Get-Pae([string]$PayloadType, [byte[]]$Payload) {
        $TypeLength = [System.Text.Encoding]::UTF8.GetByteCount($PayloadType)
        $Header = [System.Text.Encoding]::UTF8.GetBytes("DSSEv1 $TypeLength $PayloadType $($Payload.Length) ")
        $Pae = [byte[]]::new($Header.Length + $Payload.Length)
        $Header.CopyTo($Pae, 0)
        $Payload.CopyTo($Pae, $Header.Length)
        , $Pae
    }
}

Describe 'CIPP.SigstoreVerify' {
    It 'verifies the real dev bundle and reports the signing identity' {
        $Result = [CIPP.SigstoreVerify]::Verify($script:BundleJson, "sha256:$($script:Digest)", $script:Chain)
        $Result.Reason | Should -Be 'Verified'
        $Result.Verified | Should -BeTrue
        $Result.Identity | Should -Be 'https://github.com/CyberDrain/CIPP/.github/workflows/dev-container.yml@refs/heads/dev'
        $Result.Repository | Should -Be 'CyberDrain/CIPP'
        $Result.Workflow | Should -Be '.github/workflows/dev-container.yml'
        $Result.Ref | Should -Be 'refs/heads/dev'
        $Result.Commit | Should -Be '3dca57955ba5e61f11a1a0d225f9d90807f66b72'
    }

    It 'fails when the expected image digest differs' {
        $Result = [CIPP.SigstoreVerify]::Verify($script:BundleJson, ('0' * 64), $script:Chain)
        $Result.Verified | Should -BeFalse
        $Result.Stage | Should -Be 'Digest'
    }

    It 'fails the signature first when the payload subject is edited' {
        $Tampered = Edit-Bundle {
            param($b)
            $Statement = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b.dsseEnvelope.payload))
            $Statement = $Statement.Replace($script:Digest, ('0' * 64))
            $b.dsseEnvelope.payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Statement))
        }
        $Result = [CIPP.SigstoreVerify]::Verify($Tampered, ('0' * 64), $script:Chain)
        $Result.Verified | Should -BeFalse
        $Result.Stage | Should -Be 'Signature'
    }

    It 'fails when one signature byte is flipped' {
        $Tampered = Edit-Bundle {
            param($b)
            $Sig = [Convert]::FromBase64String($b.dsseEnvelope.signatures[0].sig)
            $Sig[$Sig.Length - 1] = $Sig[$Sig.Length - 1] -bxor 0x01
            $b.dsseEnvelope.signatures[0].sig = [Convert]::ToBase64String($Sig)
        }
        $Result = [CIPP.SigstoreVerify]::Verify($Tampered, $script:Digest, $script:Chain)
        $Result.Verified | Should -BeFalse
        $Result.Stage | Should -Be 'Signature'
    }

    It 'fails the chain for a self-signed look-alike certificate with a valid signature' {
        $Key = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
        $Request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=sigstore-intermediate, O=sigstore.dev', $Key, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $San = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        $San.AddUri([uri]'https://github.com/CyberDrain/CIPP/.github/workflows/dev-container.yml@refs/heads/dev')
        $Request.CertificateExtensions.Add($San.Build($true))
        $Request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509Extension]::new(
                '1.3.6.1.4.1.57264.1.1', [System.Text.Encoding]::UTF8.GetBytes('https://token.actions.githubusercontent.com'), $false))
        $Eku = [System.Security.Cryptography.OidCollection]::new()
        $null = $Eku.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $Request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($Eku, $false))
        $Cert = $Request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddMinutes(5))

        $Tampered = Edit-Bundle {
            param($b)
            $Payload = [Convert]::FromBase64String($b.dsseEnvelope.payload)
            $Pae = Get-Pae $b.dsseEnvelope.payloadType $Payload
            $Sig = $Key.SignData($Pae, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.DSASignatureFormat]::Rfc3279DerSequence)
            $b.dsseEnvelope.signatures[0].sig = [Convert]::ToBase64String($Sig)
            $b.verificationMaterial.certificate.rawBytes = [Convert]::ToBase64String($Cert.RawData)
        }
        $Result = [CIPP.SigstoreVerify]::Verify($Tampered, $script:Digest, $script:Chain)
        $Result.Verified | Should -BeFalse
        $Result.Stage | Should -Be 'Chain'
    }

    It 'fails to parse an empty or garbage bundle' -TestCases @(
        @{ Bundle = '' }
        @{ Bundle = 'not json' }
        @{ Bundle = '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json"}' }
    ) {
        param($Bundle)
        $Result = [CIPP.SigstoreVerify]::Verify($Bundle, $script:Digest, $script:Chain)
        $Result.Verified | Should -BeFalse
        $Result.Stage | Should -Be 'Parse'
    }
}
