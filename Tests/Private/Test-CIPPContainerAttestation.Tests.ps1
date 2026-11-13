# Pester tests for Test-CIPPContainerAttestation.
#
# The registry is mocked to serve a real dev-channel attestation bundle; these pin the policy
# that decides whether an auto-update may restart onto the image: repository, the workflow
# expected for the channel tag, and how transport failures are classified.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Dll = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    if (-not ('CIPP.SigstoreVerify' -as [type])) { Add-Type -Path $Dll }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPContainerAttestation.ps1')

    $env:CIPPRootPath = $RepoRoot
    $script:BundleBytes = [System.IO.File]::ReadAllBytes((Join-Path $RepoRoot 'Tests/Fixtures/ContainerAttestation/dev-fa58a723.bundle.json'))
    $script:Digest = 'sha256:fa58a723252622a45841f2cb9f0a9f8025569775d97be84f573311992584472c'
    $script:Auth = @{ Authorization = 'Bearer test' }

    function Get-RegistryResponse([string]$Uri) {
        $Body = switch -Wildcard ($Uri) {
            '*/manifests/sha256-*' {
                '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:bundlemanifest","artifactType":"application/vnd.dev.sigstore.bundle.v0.3+json"}]}'
            }
            '*/manifests/sha256:bundlemanifest' {
                '{"schemaVersion":2,"layers":[{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","digest":"sha256:bundleblob"}]}'
            }
            '*/blobs/sha256:bundleblob' { return [pscustomobject]@{ Content = $script:BundleBytes } }
        }
        # GHCR omits a charset, so PS7 hands back bytes.
        [pscustomobject]@{ Content = [System.Text.Encoding]::UTF8.GetBytes($Body) }
    }
}

Describe 'Test-CIPPContainerAttestation' {
    BeforeEach {
        Mock Invoke-WebRequest { Get-RegistryResponse $Uri }
    }

    It 'verifies a dev image built by the dev workflow' {
        $Result = Test-CIPPContainerAttestation -ImagePath 'cyberdrain/cipp' -Digest $script:Digest -Tag 'dev' -AuthHeader $script:Auth
        $Result.State | Should -Be 'Verified'
        $Result.Commit | Should -Be '3dca57955ba5e61f11a1a0d225f9d90807f66b72'
        $Result.Identity | Should -Match 'dev-container\.yml@refs/heads/dev$'
    }

    It 'fails a latest image that was not built by the release workflow' {
        $Result = Test-CIPPContainerAttestation -ImagePath 'cyberdrain/cipp' -Digest $script:Digest -Tag 'latest' -AuthHeader $script:Auth
        $Result.State | Should -Be 'Failed'
        $Result.Reason | Should -Match 'release-container\.yml'
    }

    It 'fails an image whose attestation names a different repository' {
        $Result = Test-CIPPContainerAttestation -ImagePath 'someone/cipp' -Digest $script:Digest -Tag 'dev' -AuthHeader $script:Auth
        $Result.State | Should -Be 'Failed'
        $Result.Reason | Should -Match 'expected someone/cipp'
    }

    It 'fails when no attestation is published' {
        Mock Invoke-WebRequest {
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound))
        }
        $Result = Test-CIPPContainerAttestation -ImagePath 'cyberdrain/cipp' -Digest $script:Digest -Tag 'dev' -AuthHeader $script:Auth
        $Result.State | Should -Be 'Failed'
    }

    It 'is unverifiable when the registry errors' {
        Mock Invoke-WebRequest {
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Server Error', [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError))
        }
        $Result = Test-CIPPContainerAttestation -ImagePath 'cyberdrain/cipp' -Digest $script:Digest -Tag 'dev' -AuthHeader $script:Auth
        $Result.State | Should -Be 'Unverifiable'
    }
}
