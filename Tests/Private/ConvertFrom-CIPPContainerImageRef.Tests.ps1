# linuxFxVersion can carry a tag, a digest or both; every container-update reader parses it here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/ConvertFrom-CIPPContainerImageRef.ps1')
    $script:Hex = 'b463b2a33198ba15d07246002cf59860da3a5ecddb2c73c47fb24a881b25b1e2'
}

Describe 'ConvertFrom-CIPPContainerImageRef' {
    It 'parses <Name>' -TestCases @(
        @{ Name = 'tag and digest with DOCKER prefix'; Ref = 'DOCKER|ghcr.io/cyberdrain/cipp:dev@sha256:HEX'; Base = 'ghcr.io/cyberdrain/cipp'; Tag = 'dev'; Digest = 'sha256:HEX'; Registry = 'ghcr.io' }
        @{ Name = 'tag only'; Ref = 'DOCKER|ghcr.io/cyberdrain/cipp:preview-container-attestation-verify'; Base = 'ghcr.io/cyberdrain/cipp'; Tag = 'preview-container-attestation-verify'; Digest = ''; Registry = 'ghcr.io' }
        @{ Name = 'digest only'; Ref = 'ghcr.io/cyberdrain/cipp@sha256:HEX'; Base = 'ghcr.io/cyberdrain/cipp'; Tag = ''; Digest = 'sha256:HEX'; Registry = 'ghcr.io' }
        @{ Name = 'no tag'; Ref = 'DOCKER|ghcr.io/cyberdrain/cipp'; Base = 'ghcr.io/cyberdrain/cipp'; Tag = ''; Digest = ''; Registry = 'ghcr.io' }
        @{ Name = 'registry port without tag'; Ref = 'localhost:5000/cipp'; Base = 'localhost:5000/cipp'; Tag = ''; Digest = ''; Registry = 'localhost:5000' }
        @{ Name = 'registry port with tag and digest'; Ref = 'localhost:5000/cipp:dev@sha256:HEX'; Base = 'localhost:5000/cipp'; Tag = 'dev'; Digest = 'sha256:HEX'; Registry = 'localhost:5000' }
        @{ Name = 'Docker Hub short name'; Ref = 'cipp:latest'; Base = 'cipp'; Tag = 'latest'; Digest = ''; Registry = '' }
        @{ Name = 'empty input'; Ref = ''; Base = ''; Tag = ''; Digest = ''; Registry = '' }
    ) {
        param($Ref, $Base, $Tag, $Digest, $Registry)
        $Result = ConvertFrom-CIPPContainerImageRef -Reference ($Ref -replace 'HEX', $script:Hex)
        $Result.Base | Should -Be $Base
        $Result.Tag | Should -Be $Tag
        $Result.Digest | Should -Be ($Digest -replace 'HEX', $script:Hex)
        $Result.Registry | Should -Be $Registry
    }
}
