# Pester tests for MCP resource-client selection in Invoke-PublicMcpRegister.
#
# This anonymous RFC 7591 endpoint hands an MCP client (Claude, ChatGPT, ...) the client_id of the
# instance's MCP resource app registration. Issue #619: failed setups left several API clients with
# MCPAllowed set, and one whose Entra app registration no longer existed got advertised, so every
# connect failed at authorize with AADSTS700016. The endpoint now advertises only a holder whose app
# registration still resolves in Entra, and skips stale ones.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/MCP/Invoke-PublicMcpRegister.ps1'
    $ErrorHelperPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/MCP/New-CippMcpRegistrationError.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-PublicMcpRegister.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Headers
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp, $tenantid, [switch]$ComplexFilter, $Select) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippMcpKnownClients {
        [pscustomobject]@{
            PublicClientRedirectUris = @()
            ConfidentialRedirectUris = @()
            PreAuthorizedClientIds   = @()
        }
    }

    . $ErrorHelperPath
    . $FunctionPath

    # Loopback callback passes redirect validation directly, so no redirect-URI Graph call fires and
    # the tests isolate the app-registration existence check.
    function New-RegisterRequest {
        param([string[]]$RedirectUris = @('http://127.0.0.1:52100/callback'))
        [pscustomobject]@{
            Method  = 'POST'
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'PublicMcpRegister' }
            Body    = [pscustomobject]@{
                client_name   = 'Test MCP client'
                redirect_uris = $RedirectUris
            }
        }
    }
}

Describe 'Invoke-PublicMcpRegister - advertising a live MCP resource client' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        # Reset the per-runspace existence cache so a verdict from one test can't leak into the next.
        $script:McpResourceAppExistsCache = $null
        $script:McpResourceAppRedirectCache = $null
    }

    It 'returns an error when no client holds MCP Access' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph must not be called when no client holds MCP Access' }

        $Response = Invoke-PublicMcpRegister -Request (New-RegisterRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        ($Response.Body | ConvertFrom-Json).error_description | Should -BeLike '*No MCP client is configured*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'advertises the holder when its app registration exists' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ RowKey = 'live-app'; MCPAllowed = $true; Enabled = $true })
        }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = 'live-app' } }

        $Response = Invoke-PublicMcpRegister -Request (New-RegisterRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Created)
        ($Response.Body | ConvertFrom-Json).client_id | Should -Be 'live-app'
    }

    It 'refuses to advertise a stale holder whose app registration is gone' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ RowKey = 'stale-app'; MCPAllowed = $true; Enabled = $true })
        }
        # No application matches the appId filter -> the app registration no longer exists.
        Mock -CommandName New-GraphGetRequest -MockWith { @() }

        $Response = Invoke-PublicMcpRegister -Request (New-RegisterRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        ($Response.Body | ConvertFrom-Json).error_description | Should -BeLike '*no longer has a valid app registration*'
    }

    It 'skips a stale holder and advertises a live one when both are flagged' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ RowKey = 'stale-app'; MCPAllowed = $true; Enabled = $true }
                [pscustomobject]@{ RowKey = 'live-app'; MCPAllowed = $true; Enabled = $true }
            )
        }
        Mock -CommandName New-GraphGetRequest -MockWith { @() } -ParameterFilter { $uri -like "*'stale-app'*" }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = 'live-app' } } -ParameterFilter { $uri -like "*'live-app'*" }

        $Response = Invoke-PublicMcpRegister -Request (New-RegisterRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Created)
        ($Response.Body | ConvertFrom-Json).client_id | Should -Be 'live-app'
    }

    It 'advertises the holder rather than blocking when the existence check errors' {
        # A transient Graph outage must not break every connect, so an unverifiable client is served.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ RowKey = 'unverified-app'; MCPAllowed = $true; Enabled = $true })
        }
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph is having a moment' }

        $Response = Invoke-PublicMcpRegister -Request (New-RegisterRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Created)
        ($Response.Body | ConvertFrom-Json).client_id | Should -Be 'unverified-app'
    }

    It 'pins the client app when ?client= scopes the request to a specific MCPAllowed client' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ RowKey = 'client-a'; MCPAllowed = $true; Enabled = $true }
                [pscustomobject]@{ RowKey = 'client-b'; MCPAllowed = $true; Enabled = $true }
            )
        }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = 'client-b' } }

        $Request = New-RegisterRequest
        $Request.Params.client = 'client-b'
        $Request | Add-Member -NotePropertyName Query -NotePropertyValue ([pscustomobject]@{ client = 'client-b' }) -Force

        $Response = Invoke-PublicMcpRegister -Request $Request

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Created)
        ($Response.Body | ConvertFrom-Json).client_id | Should -Be 'client-b'
    }

    It 'errors when ?client= matches no enabled MCP client' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([pscustomobject]@{ RowKey = 'client-a'; MCPAllowed = $true; Enabled = $true })
        }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = 'client-a' } }

        $Request = New-RegisterRequest
        $Request | Add-Member -NotePropertyName Query -NotePropertyValue ([pscustomobject]@{ client = 'does-not-exist' }) -Force

        $Response = Invoke-PublicMcpRegister -Request $Request

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
