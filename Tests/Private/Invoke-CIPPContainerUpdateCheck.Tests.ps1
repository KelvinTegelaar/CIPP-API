# Writing linuxFxVersion recycles the container, so the verified digest is pinned only where a
# restart is intended, and an unverified image never moves the pin.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Invoke-CIPPContainerUpdateCheck.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/ConvertFrom-CIPPContainerImageRef.ps1')

    function Get-CippTable { param($tablename) @{} }
    function Sync-CippContainerUpdateState { }
    function Get-CIPPAzFunctionAppSubId { }
    function Get-CIPPFunctionAppResourceGroup { param($SiteName) }
    function New-CIPPAzRestRequest { param($Uri, $Method, $Body, $ContentType) }
    function Get-CIPPGHCRImageInfo { param($ImagePath, $Tag) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CIPPContainerAttestation { param($ImagePath, $Digest, $Tag, $AuthHeader) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Request-CIPPRestart { param($Reason) }

    $script:Remote = 'sha256:fa58a723252622a45841f2cb9f0a9f8025569775d97be84f573311992584472c'
    $script:Old = 'sha256:b463b2a33198ba15d07246002cf59860da3a5ecddb2c73c47fb24a881b25b1e2'
}

Describe 'Invoke-CIPPContainerUpdateCheck pin rule' {
    BeforeEach {
        $env:APP_VERSION = '1.0.0'
        $env:WEBSITE_SITE_NAME = 'cipp-test'
        $script:LinuxFx = 'DOCKER|ghcr.io/cyberdrain/cipp:dev'
        $script:RemoteVersion = '1.0.1'
        $script:State = 'Verified'
        $script:Settings = [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '1h'; CheckTime = ''; RunningAttestationState = 'Unpinned' }

        Mock Get-CIPPAzFunctionAppSubId { 'sub' }
        Mock Get-CIPPFunctionAppResourceGroup { 'rg' }
        Mock New-CIPPAzRestRequest { @{ properties = @{ linuxFxVersion = $script:LinuxFx } } }
        Mock Get-CIPPGHCRImageInfo { [pscustomobject]@{ Digest = $script:Remote; Version = $script:RemoteVersion; Created = '2026-11-01T00:00:00Z'; AuthHeader = @{} } }
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = $script:State; Reason = 'reason' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Request-CIPPRestart { }
    }

    It 'auto-update pins the verified digest in one write and requests no second restart' {
        $Result = Invoke-CIPPContainerUpdateCheck -Settings $script:Settings
        $Result.Restarted | Should -BeTrue
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Remote)" }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PinnedDigest -eq $script:Remote -and $Entity.RunningAttestationState -eq 'Unpinned' }
    }

    It 'replaces an older pin and keeps the tag on auto-update' {
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        Invoke-CIPPContainerUpdateCheck -Settings $script:Settings | Out-Null
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Remote)" }
    }

    It 'restarts explicitly when the verified update is already pinned' {
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Remote)"
        Invoke-CIPPContainerUpdateCheck -Settings $script:Settings | Out-Null
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke Request-CIPPRestart -Times 1 -Exactly
    }

    It 'does not pin a verified update while auto-restart is off' {
        $script:Settings.AutoUpdate = 'false'
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        $Result = Invoke-CIPPContainerUpdateCheck -Settings $script:Settings
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
        $Result.PinnedDigest | Should -Be $script:Old
    }

    It 'never moves the pin for a <State> image' -TestCases @(@{ State = 'Failed' }, @{ State = 'Unverifiable' }) {
        param($State)
        $script:State = $State
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        Invoke-CIPPContainerUpdateCheck -Settings $script:Settings | Out-Null
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.PinnedDigest -eq $script:Old }
    }

    It 'pins the running build once when unpinned and up to date' {
        $script:RemoteVersion = '1.0.0'
        $Result = Invoke-CIPPContainerUpdateCheck -Settings $script:Settings
        $Result.PinChanged | Should -BeTrue
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Remote)" }
    }

    It 'leaves an existing pin alone when up to date' {
        $script:RemoteVersion = '1.0.0'
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        Invoke-CIPPContainerUpdateCheck -Settings $script:Settings | Out-Null
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'checks the tag, not the digest, of a pinned reference' {
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        Invoke-CIPPContainerUpdateCheck -Settings $script:Settings | Out-Null
        Should -Invoke Get-CIPPGHCRImageInfo -Times 1 -Exactly -ParameterFilter { $ImagePath -eq 'cyberdrain/cipp' -and $Tag -eq 'dev' }
    }

    It 'channel switch writes tag and verified digest in one write' {
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        $Result = Invoke-CIPPContainerUpdateCheck -Settings $script:Settings -Channel 'latest'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:latest@$($script:Remote)" }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
        $Result.Tag | Should -Be 'latest'
    }

    It 'channel switch to an unverified tag writes the bare tag' {
        $script:State = 'Failed'
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        $Result = Invoke-CIPPContainerUpdateCheck -Settings $script:Settings -Channel 'latest'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq 'DOCKER|ghcr.io/cyberdrain/cipp:latest' }
        $Result.PinnedDigest | Should -Be ''
    }
}
