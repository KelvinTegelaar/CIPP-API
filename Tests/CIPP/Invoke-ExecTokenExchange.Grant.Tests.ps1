# ExecTokenExchange exists only for the SAM setup wizard's authorization-code exchange. It must refuse any
# other grant (client_credentials would mint SAM app-only tokens for any tenant), pin the token endpoint to
# /organizations, forward only the wizard's fields, and bind client_id to this instance's SAM app.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Setup/Invoke-ExecTokenExchange.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$Headers
    }

    function Get-CippKeyVaultName { 'kv' }
    function Get-CIPPAuthentication { $true }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPSAMCertificate { param([switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) 'assertion' }
    function Write-LogMessage { param($API, $message, $Sev) }

    . $FunctionPath

    $script:GoodUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token'

    function New-Req {
        param($TokenRequest, $TokenUrl = $script:GoodUrl)
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecTokenExchange' }
            Body   = [pscustomobject]@{ tokenRequest = $TokenRequest; tokenUrl = $TokenUrl; tenantId = 'app-id' }
        }
    }
}

Describe 'Invoke-ExecTokenExchange grant and field locking' {
    BeforeEach {
        # Secret-mode so no certificate is needed; a real SAM app id so client_id binding engages.
        $env:ApplicationSecret = 'a-usable-secret'
        $env:ApplicationID = '11111111-1111-1111-1111-111111111111'
        Remove-Item Env:\CertificateAuthMode -ErrorAction SilentlyContinue
        $script:Captured = $null
        Mock Invoke-RestMethod { $script:Captured = $Body; @{ access_token = 'token' } }
    }
    AfterAll {
        Remove-Item Env:\ApplicationSecret, Env:\ApplicationID -ErrorAction SilentlyContinue
    }

    It 'rejects client_credentials without ever calling the token endpoint' {
        $req = New-Req ([pscustomobject]@{ grant_type = 'client_credentials'; client_id = 'attacker-app'; scope = 'https://graph.microsoft.com/.default' })
        $resp = Invoke-ExecTokenExchange -Request $req
        $resp.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $resp.Body.error | Should -Be 'unsupported_grant_type'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'rejects a token URL that is not the /organizations endpoint' {
        $req = New-Req ([pscustomobject]@{ grant_type = 'authorization_code'; code = 'c'; code_verifier = 'v' }) `
            'https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/oauth2/v2.0/token'
        $resp = Invoke-ExecTokenExchange -Request $req
        $resp.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'forwards only allowlisted fields and binds client_id to the SAM app' {
        $req = New-Req ([pscustomobject]@{
                grant_type    = 'authorization_code'
                client_id     = 'attacker-app'
                code          = 'the-code'
                redirect_uri  = 'https://cipp/authredirect'
                code_verifier = 'pkce'
                resource      = 'https://graph.microsoft.com'   # injected, must be dropped
                requested_token_use = 'on_behalf_of'            # injected, must be dropped
            })
        $resp = Invoke-ExecTokenExchange -Request $req
        $resp.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Captured.Keys | Should -Not -Contain 'resource'
        $script:Captured.Keys | Should -Not -Contain 'requested_token_use'
        $script:Captured['grant_type'] | Should -Be 'authorization_code'
        $script:Captured['code'] | Should -Be 'the-code'
        $script:Captured['client_id'] | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'still completes the legitimate wizard exchange' {
        $req = New-Req ([pscustomobject]@{ grant_type = 'authorization_code'; client_id = '11111111-1111-1111-1111-111111111111'; code = 'c'; redirect_uri = 'https://cipp/authredirect'; code_verifier = 'v' })
        $resp = Invoke-ExecTokenExchange -Request $req
        $resp.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $resp.Body.access_token | Should -Be 'token'
        Should -Invoke Invoke-RestMethod -Times 1
    }
}
