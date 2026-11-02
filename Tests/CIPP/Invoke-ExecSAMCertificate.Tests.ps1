# The Get action must expose certificate metadata and the credentials registered on the SAM app,
# and never the certificate itself or any key material.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecSAMCertificate.ps1'
    $NewCertPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/New-CIPPSAMCertificate.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function Update-CIPPSAMCertificate { param([switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{} }

    . $NewCertPath
    . $FunctionPath

    $script:Cert = New-CIPPSAMCertificate -SubjectName 'CN=CIPP-SAM-Test'
    $script:Request = [pscustomobject]@{ Body = @{ Action = 'Get' }; Query = @{} }
}

Describe 'Invoke-ExecSAMCertificate Get' {
    BeforeEach {
        $env:ApplicationID = 'sam-app-id'
        Mock Get-CIPPSAMCertificate { $script:Cert }
        Mock New-GraphGetRequest {
            $Bytes = [Convert]::FromHexString($script:Cert.Thumbprint)
            [pscustomobject]@{
                id             = 'obj'
                keyCredentials = @(
                    [pscustomobject]@{ type = 'AsymmetricX509Cert'; displayName = 'b64'; keyId = 'k1'; customKeyIdentifier = [Convert]::ToBase64String($Bytes) }
                    [pscustomobject]@{ type = 'AsymmetricX509Cert'; displayName = 'hex'; keyId = 'k2'; customKeyIdentifier = $script:Cert.Thumbprint.ToLowerInvariant() }
                    [pscustomobject]@{ type = 'AsymmetricX509Cert'; displayName = 'other'; keyId = 'k3'; customKeyIdentifier = ('AB' * 20) }
                    [pscustomobject]@{ type = 'Symmetric'; displayName = 'secret'; keyId = 'k4'; customKeyIdentifier = $null }
                )
            }
        }
    }

    It 'returns Subject and the registered credentials with ThisInstance flagged' {
        $Body = (Invoke-ExecSAMCertificate -Request $script:Request).Body
        $Body.Subject | Should -Be 'CN=CIPP-SAM-Test'
        $Body.RegisteredCertificates.Count | Should -Be 3
        ($Body.RegisteredCertificates | Where-Object ThisInstance).DisplayName | Should -Be @('b64', 'hex')
        ($Body.RegisteredCertificates | Where-Object DisplayName -eq 'other').ThisInstance | Should -BeFalse
        $Body.RegisteredCertificates[0].Thumbprint | Should -Be $script:Cert.Thumbprint
        $Body.RegisteredCertificates[1].Thumbprint | Should -Be $script:Cert.Thumbprint
    }

    It 'returns the application id' {
        (Invoke-ExecSAMCertificate -Request $script:Request).Body.ApplicationId | Should -Be 'sam-app-id'
    }

    It 'never includes the certificate or key material' {
        $Body = (Invoke-ExecSAMCertificate -Request $script:Request).Body
        $Body.Keys | Should -Not -Contain 'Certificate'
        $Body.Keys | Should -Not -Contain 'PfxBase64'
        ($Body | ConvertTo-Json -Depth 5) | Should -Not -Match 'PfxBase64'
    }

    It 'returns an empty list when the Graph call fails' {
        Mock New-GraphGetRequest { throw 'boom' }
        $Body = (Invoke-ExecSAMCertificate -Request $script:Request).Body
        @($Body.RegisteredCertificates).Count | Should -Be 0
        $Body.Subject | Should -Be 'CN=CIPP-SAM-Test'
    }
}
