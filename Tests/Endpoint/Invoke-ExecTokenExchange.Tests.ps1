# Pester tests for Invoke-ExecTokenExchange certificate assertions.
# The Direct Add / SAM OAuth popup posts to the /organizations token endpoint. When certificate
# auth is on, the client assertion aud claim must equal that tokenUrl - using $env:TenantID
# (partner GUID) produces AADSTS700023.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecTokenExchange.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecTokenExchange.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
        [object]$Headers
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippKeyVaultName { 'test-kv' }
    function Write-LogMessage { param($API, $message, $Sev) }
    function Get-CIPPAuthentication { $true }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }
    function Invoke-RestMethod {
        param($Uri, $Method, $Body, $ContentType, [switch]$SkipHttpErrorCheck)
    }

    . $FunctionPath

    function New-TokenExchangeRequest {
        param(
            [string]$TokenUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
            [string]$AppId = 'sam-app-id'
        )
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecTokenExchange' }
            Body   = [pscustomobject]@{
                tokenUrl     = $TokenUrl
                tenantId     = $AppId
                tokenRequest = [pscustomobject]@{
                    grant_type   = 'authorization_code'
                    client_id    = $AppId
                    code         = 'auth-code'
                    redirect_uri = 'https://cipp.example.com/authredirect'
                }
            }
        }
    }
}

Describe 'Invoke-ExecTokenExchange certificate assertion audience' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationSecret', 'TenantID', 'AzureWebJobsStorage', 'NonLocalHostAzurite') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        # Partner tenant GUID - the regression was using this as aud instead of tokenUrl.
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:CertificateAuthMode = $true
        $env:ApplicationSecret = 'AppSecret'
        Remove-Item env:AzureWebJobsStorage -ErrorAction SilentlyContinue
        Remove-Item env:NonLocalHostAzurite -ErrorAction SilentlyContinue

        Mock Write-LogMessage {}
        Mock Get-CippKeyVaultName { 'test-kv' }
        Mock Get-CIPPAuthentication { $true }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'CERT-OBJECT'; Thumbprint = 'ABC' } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt.assertion' }
        Mock Invoke-RestMethod { @{ access_token = 'token'; refresh_token = 'refresh'; expires_in = 3600 } }
        Mock Start-Sleep {}
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) {
                Remove-Item "env:$Name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "env:$Name" -Value $script:SavedEnv[$Name]
            }
        }
    }

    It 'builds the certificate assertion aud from the organizations tokenUrl, not env:TenantID' {
        $TokenUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token'
        $Response = Invoke-ExecTokenExchange -Request (New-TokenExchangeRequest -TokenUrl $TokenUrl) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-CIPPCertificateAssertion -Times 1 -Exactly -ParameterFilter {
            $Audience -eq $TokenUrl -and
            $TenantId -eq 'organizations' -and
            $AppId -eq 'sam-app-id'
        }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq $TokenUrl -and
            $Body.ContainsKey('client_assertion') -and
            $Body['client_assertion_type'] -eq 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer' -and
            -not $Body.ContainsKey('client_secret')
        }
    }
}
