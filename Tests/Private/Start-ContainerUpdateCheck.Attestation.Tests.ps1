# Pester tests for the provenance handling in Start-ContainerUpdateCheck.
#
# The channel image is verified on every check, but only a pending update that fails
# verification is worth a Warning; an up-to-date instance on an unattested channel logs nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-ContainerUpdateCheck.ps1')

    function Get-CippTable { param($tablename) @{} }
    function Sync-CippContainerUpdateState { }
    function Get-CIPPAzFunctionAppSubId { }
    function Get-CIPPFunctionAppResourceGroup { param($SiteName) }
    function New-CIPPAzRestRequest { param($Uri, $Method) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CIPPContainerAttestation { param($ImagePath, $Digest, $Tag, $AuthHeader) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Request-CIPPRestart { param($Reason) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    $script:Digest = 'sha256:fa58a723252622a45841f2cb9f0a9f8025569775d97be84f573311992584472c'
}

Describe 'Start-ContainerUpdateCheck provenance' {
    BeforeEach {
        $env:APP_VERSION = '1.0.0'
        $env:WEBSITE_SITE_NAME = 'cipp-test'
        $script:RemoteVersion = '1.0.0'
        $script:State = 'Failed'

        Mock Sync-CippContainerUpdateState { [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '1h'; CheckTime = '' } }
        Mock Get-CIPPAzFunctionAppSubId { 'sub' }
        Mock Get-CIPPFunctionAppResourceGroup { 'rg' }
        Mock New-CIPPAzRestRequest { @{ properties = @{ linuxFxVersion = 'DOCKER|ghcr.io/cyberdrain/cipp:dev' } } }
        Mock Invoke-RestMethod { @{ token = 'anon' } }
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Headers = @{ 'Docker-Content-Digest' = $script:Digest }
                Content = (@{ annotations = @{ 'org.opencontainers.image.version' = $script:RemoteVersion; 'org.opencontainers.image.created' = '2026-11-01T00:00:00Z' } } | ConvertTo-Json)
            }
        }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = $script:State; Reason = 'No Sigstore attestation is published for this image' } }
        Mock Write-LogMessage { }
        Mock Request-CIPPRestart { }
    }

    It 'verifies the channel image and stores the result when no update is available' {
        Start-ContainerUpdateCheck
        Should -Invoke Test-CIPPContainerAttestation -Times 1 -Exactly -ParameterFilter { $Digest -eq $script:Digest -and $Tag -eq 'dev' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AttestationState -eq 'Failed' -and $Entity.UpdateAvailable -eq 'False' }
    }

    It 'logs no warning for an up-to-date instance whose channel image is unattested' -TestCases @(
        @{ State = 'Failed' }
        @{ State = 'Unverifiable' }
    ) {
        param($State)
        $script:State = $State
        Start-ContainerUpdateCheck
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'warns and withholds the restart when a pending update fails verification' {
        $script:RemoteVersion = '1.0.1'
        Start-ContainerUpdateCheck
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*Auto-restart withheld*' }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
    }
}
