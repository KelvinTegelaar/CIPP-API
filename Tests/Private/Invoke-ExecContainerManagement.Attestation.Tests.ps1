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

    function Get-CippTable { param($tablename) @{} }
    function Sync-CippContainerUpdateState { }
    function Get-CIPPAzFunctionAppSubId { }
    function Get-CIPPFunctionAppResourceGroup { param($SiteName) }
    function New-CIPPAzRestRequest { param($Uri, $Method) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CIPPContainerAttestation { param($ImagePath, $Digest, $Tag, $AuthHeader) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Request-CIPPRestart { param($Reason) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

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

    It 'stores the attestation result and restarts on a verified update' {
        $Response = Invoke-ExecContainerManagement -Request $script:Request -TriggerMetadata @{}
        $Response.StatusCode | Should -Be 200
        Should -Invoke Test-CIPPContainerAttestation -Times 1 -Exactly -ParameterFilter { $ImagePath -eq 'cyberdrain/cipp' -and $Digest -eq $script:Digest -and $Tag -eq 'dev' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.AttestationState -eq 'Verified' -and $Entity.UpdateAvailable -eq 'True' }
        Should -Invoke Request-CIPPRestart -Times 1 -Exactly
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
