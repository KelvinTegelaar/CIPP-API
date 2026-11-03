# The boot check records whether the image App Service will keep running is pinned, attested,
# and built from the same commit as the code that is actually running.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPRunningImageProvenance.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/ConvertFrom-CIPPContainerImageRef.ps1')

    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzFunctionAppSubId { }
    function Get-CIPPFunctionAppResourceGroup { param($SiteName) }
    function New-CIPPAzRestRequest { param($Uri, $Method) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CIPPContainerAttestation { param($ImagePath, $Digest, $Tag, $AuthHeader) }

    $script:Digest = 'sha256:b463b2a33198ba15d07246002cf59860da3a5ecddb2c73c47fb24a881b25b1e2'
    $script:Commit = '81366c69a0c9739487400a9e00bd85b4492a1453'
}

Describe 'Test-CIPPRunningImageProvenance' {
    BeforeEach {
        $env:WEBSITE_SITE_NAME = 'cipp-test'
        $env:COMMIT_SHA = $script:Commit
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Digest)"
        $script:AttestedCommit = $script:Commit

        Mock Get-CIPPAzFunctionAppSubId { 'sub' }
        Mock Get-CIPPFunctionAppResourceGroup { 'rg' }
        Mock New-CIPPAzRestRequest { @{ properties = @{ linuxFxVersion = $script:LinuxFx } } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'Settings'; RowKey = 'UpdateConfig'; AutoUpdate = 'false'; RemoteVersion = '1.0.1' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = 'Verified'; Reason = 'Signed by the release workflow'; Commit = $script:AttestedCommit } }
    }

    It 'records Unpinned without verifying when the site config names only a tag' {
        $script:LinuxFx = 'DOCKER|ghcr.io/cyberdrain/cipp:dev'
        Test-CIPPRunningImageProvenance
        Should -Invoke Test-CIPPContainerAttestation -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RunningAttestationState -eq 'Unpinned' -and $Entity.RunningDigest -eq '' -and $Entity.RunningAttestationReason }
    }

    It 'verifies the pinned digest against its tag and keeps the other row fields' {
        Test-CIPPRunningImageProvenance
        Should -Invoke Test-CIPPContainerAttestation -Times 1 -Exactly -ParameterFilter { $ImagePath -eq 'cyberdrain/cipp' -and $Digest -eq $script:Digest -and $Tag -eq 'dev' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.RunningAttestationState -eq 'Verified' -and $Entity.RunningDigest -eq $script:Digest -and $Entity.AutoUpdate -eq 'false' -and $Entity.RemoteVersion -eq '1.0.1'
        }
    }

    It 'fails a verified image whose attested commit is not the running build' {
        $script:AttestedCommit = 'ffffffffffffffffffffffffffffffffffffffff'
        Test-CIPPRunningImageProvenance
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RunningAttestationState -eq 'Failed' -and $Entity.RunningAttestationReason -like '*does not match the running build*' }
    }

    It 'never throws' {
        Mock New-CIPPAzRestRequest { throw 'ARM down' }
        { Test-CIPPRunningImageProvenance } | Should -Not -Throw
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
