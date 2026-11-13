# Pester tests for the provenance handling in the manual CheckUpdate action.
#
# The button path must store the same attestation result as the timer and never
# auto-restart onto an image that failed verification.

BeforeAll {
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecContainerManagement.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Invoke-CIPPContainerUpdateCheck.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPGHCRImageInfo.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/ConvertFrom-CIPPContainerImageRef.ps1')

    function Get-CippTable { param($tablename) @{} }
    function Sync-CippContainerUpdateState { }
    function Get-CIPPAzFunctionAppSubId { }
    function Get-CIPPFunctionAppResourceGroup { param($SiteName) }
    function New-CIPPAzRestRequest { param($Uri, $Method, $Body, $ContentType) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CIPPContainerAttestation { param($ImagePath, $Digest, $Tag, $AuthHeader) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Request-CIPPRestart { param($Reason) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-CIPPVersionHistory { param($Last) }

    $script:Digest = 'sha256:fa58a723252622a45841f2cb9f0a9f8025569775d97be84f573311992584472c'
}

Describe 'Invoke-ExecContainerManagement CheckUpdate provenance' {
    BeforeEach {
        $env:APP_VERSION = '1.0.0'
        $env:WEBSITE_SITE_NAME = 'cipp-test'
        $script:State = 'Verified'

        Mock Sync-CippContainerUpdateState { [pscustomobject]@{ AutoUpdate = 'true'; CheckInterval = '1h'; CheckTime = '' } }
        Mock Get-CIPPAzFunctionAppSubId { 'sub' }
        Mock Get-CIPPFunctionAppResourceGroup { 'rg' }
        Mock New-CIPPAzRestRequest { @{ properties = @{ linuxFxVersion = 'DOCKER|ghcr.io/cyberdrain/cipp:dev' } } }
        Mock Invoke-RestMethod { @{ token = 'anon' } }
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Headers = @{ 'Docker-Content-Digest' = $script:Digest }
                Content = (@{ annotations = @{ 'org.opencontainers.image.version' = '1.0.1'; 'org.opencontainers.image.created' = '2026-11-01T00:00:00Z' } } | ConvertTo-Json)
            }
        }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = $script:State; Reason = 'No Sigstore attestation is published for this image' } }
        Mock Write-LogMessage { }
        Mock Request-CIPPRestart { }

        $script:Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'CheckUpdate' }; Body = @{} }
    }

    It 'stores the attestation result and restarts on a verified update by pinning it' {
        $Response = Invoke-ExecContainerManagement -Request $script:Request -TriggerMetadata @{}
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike '*restart initiated*'
        Should -Invoke Test-CIPPContainerAttestation -Times 1 -Exactly -ParameterFilter { $ImagePath -eq 'cyberdrain/cipp' -and $Digest -eq $script:Digest -and $Tag -eq 'dev' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AttestationState -eq 'Verified' -and $Entity.UpdateAvailable -eq 'True' -and $Entity.PinnedDigest -eq $script:Digest }
        # The linuxFxVersion write recycles the container, so no second restart is requested.
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Digest)" }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
    }

    It 'withholds the restart and warns when the update fails verification' {
        $script:State = 'Failed'
        $Response = Invoke-ExecContainerManagement -Request $script:Request -TriggerMetadata @{}
        $Response.Body.Results | Should -BeLike '*withheld*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AttestationState -eq 'Failed' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*Auto-restart withheld*' }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
    }
}

Describe 'Invoke-ExecContainerManagement digest pinning' {
    BeforeEach {
        $env:APP_VERSION = '1.0.0'
        $env:IMAGE_TAG = 'dev'
        $env:WEBSITE_SITE_NAME = 'cipp-test'
        $script:Old = 'sha256:b463b2a33198ba15d07246002cf59860da3a5ecddb2c73c47fb24a881b25b1e2'
        $script:LinuxFx = "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Old)"
        $script:Settings = [pscustomobject]@{
            PartitionKey = 'Settings'; RowKey = 'UpdateConfig'; AutoUpdate = 'false'; CheckInterval = '1h'; CheckTime = ''
            AttestationState = 'Verified'; RemoteDigest = $script:Digest; CheckedTag = 'dev'; PinnedDigest = $script:Old
            RunningAttestationState = 'Failed'; RunningAttestationReason = 'attested commit does not match'; RunningDigest = $script:Old
        }

        Mock Sync-CippContainerUpdateState { $script:Settings }
        Mock Get-CIPPAzFunctionAppSubId { 'sub' }
        Mock Get-CIPPFunctionAppResourceGroup { 'rg' }
        Mock New-CIPPAzRestRequest { @{ properties = @{ linuxFxVersion = $script:LinuxFx } } }
        Mock Invoke-RestMethod { @{ token = 'anon' } }
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Headers = @{ 'Docker-Content-Digest' = $script:Digest }
                Content = (@{ annotations = @{ 'org.opencontainers.image.version' = '1.0.1'; 'org.opencontainers.image.created' = '2026-11-01T00:00:00Z' } } | ConvertTo-Json)
            }
        }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = 'Verified'; Reason = '' } }
        Mock Write-LogMessage { }
        Mock Request-CIPPRestart { }
        Mock Get-CIPPVersionHistory { }
    }

    It 'Status reports the tag as the configured channel and returns the pin fields' {
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'Status' }; Body = @{} }
        $Results = (Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}).Body.Results
        $Results.ConfiguredChannel | Should -Be 'dev'
        $Results.UpdateSettings.PinnedDigest | Should -Be $script:Old
        $Results.UpdateSettings.RunningAttestationState | Should -Be 'Failed'
        $Results.UpdateSettings.RunningAttestationReason | Should -Be 'attested commit does not match'
        $Results.UpdateSettings.RunningDigest | Should -Be $script:Old
    }

    It 'Restart pins the verified channel digest and lets that write restart the container' {
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'Restart' }; Body = @{} }
        $Response = Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}
        $Response.Body.Results | Should -BeLike '*pinned to sha256:fa58a7232526*'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:dev@$($script:Digest)" }
        Should -Invoke Request-CIPPRestart -Times 0 -Exactly
    }

    It 'Restart keeps the pin when the channel image is not verified' {
        $script:Settings.AttestationState = 'Failed'
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'Restart' }; Body = @{} }
        Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{} | Out-Null
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        Should -Invoke Request-CIPPRestart -Times 1 -Exactly
    }

    It 'UpdateChannel pins a verified channel in a single write' {
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'UpdateChannel' }; Body = @{ Channel = 'latest' } }
        $Response = Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike '*Pinned to sha256:fa58a7232526*'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq "DOCKER|ghcr.io/cyberdrain/cipp:latest@$($script:Digest)" }
    }

    It 'UpdateChannel writes the bare tag and says why when the channel does not verify' {
        Mock Test-CIPPContainerAttestation { [pscustomobject]@{ State = 'Failed'; Reason = 'No Sigstore attestation is published for this image' } }
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'UpdateChannel' }; Body = @{ Channel = 'latest' } }
        $Response = Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}
        $Response.Body.Results | Should -BeLike '*Not pinned: provenance Failed*'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq 'DOCKER|ghcr.io/cyberdrain/cipp:latest' }
    }

    It 'UpdateChannel writes the bare standard-channel tag when the registry is unreachable' {
        Mock Invoke-WebRequest { throw 'registry unreachable' }
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'UpdateChannel' }; Body = @{ Channel = 'latest' } }
        $Response = Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike '*Not pinned: the registry could not be reached (registry unreachable)*'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Body.properties.linuxFxVersion -eq 'DOCKER|ghcr.io/cyberdrain/cipp:latest' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AttestationState -eq 'Unverifiable' -and $Entity.PinnedDigest -eq '' -and $Entity.CheckedTag -eq 'latest' }
    }

    It 'UpdateChannel returns 404 for a swept branch build without writing' {
        Mock Invoke-WebRequest { throw 'manifest unknown' }
        $Request = @{ Params = @{ CIPPEndpoint = 'ExecContainerManagement' }; Headers = @{}; Query = @{ Action = 'UpdateChannel' }; Body = @{ Channel = 'feat-gone' } }
        $Response = Invoke-ExecContainerManagement -Request $Request -TriggerMetadata @{}
        $Response.StatusCode | Should -Be 404
        Should -Invoke New-CIPPAzRestRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }
}
