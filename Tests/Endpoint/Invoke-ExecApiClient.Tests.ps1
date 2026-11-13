# Pester tests for MCP client handling in Invoke-ExecApiClient (AddUpdate).
#
# Split-app model: an MCPAllowed API client is an OAuth *client* (the app a connector signs in as),
# and the dedicated CIPP-MCP app is the shared resource. Several MCPAllowed clients may coexist, each
# with its own redirects, so saving one must NOT clear MCP Access on the others. Enabling
# MCP on a client configures it via Set-CIPPMCPClientApp.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecApiClient.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecApiClient.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Test-CippApiClientRoleGrant { param($Request, $Role) @{ Allowed = $true; Message = '' } }
    function New-CIPPAPIConfig { param($Headers, $ClientId, $AppName, [switch]$ResetSecret) [pscustomobject]@{ ApplicationID = 'new-app'; AppName = 'New Client'; Results = 'ok' } }
    function Set-CIPPMCPClientApp { param($AppId, $Headers) @{ Success = $true; ClientAppId = $AppId; ResourceAppId = 'resource-app' } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippProtectedAppId { @() }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $asapp, [switch]$ComplexFilter) }
    function Get-CIPPSiteHostname { param([switch]$AsRedirectUri) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    function New-AddUpdateRequest {
        param([bool]$McpAllowed)
        [pscustomobject]@{
            Headers = @{}
            Query   = [pscustomobject]@{ Action = 'AddUpdate' }
            Params  = @{ CIPPEndpoint = 'ExecApiClient' }
            Body    = [pscustomobject]@{
                Action     = 'AddUpdate'
                AppName    = 'New Client'
                Role       = [pscustomobject]@{ value = 'readonly' }
                Enabled    = $true
                MCPAllowed = $McpAllowed
                IpRange    = [pscustomobject]@{ value = @() }
            }
        }
    }
}

Describe 'Invoke-ExecApiClient - MCP client configuration' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPMCPClientApp -MockWith { @{ Success = $true; ClientAppId = $AppId; ResourceAppId = 'resource-app' } }

        # The new client's RowKey lookup finds nothing (it's new); the unfiltered roster scan returns
        # an existing client that already holds MCP Access.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null } -ParameterFilter { $Filter -like 'RowKey eq*' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'other-mcp'; AppName = 'Other MCP'; Role = 'readonly'; MCPAllowed = $true; Enabled = $true }
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'plain'; AppName = 'Plain'; Role = 'readonly'; MCPAllowed = $false; Enabled = $true }
            )
        } -ParameterFilter { -not $Filter }

        $script:SavedEntities = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            $script:SavedEntities.Add(($Entity | ConvertTo-Json -Depth 6 | ConvertFrom-Json))
        }
    }

    It 'allows multiple MCP clients - saving one does not clear MCP Access on others' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $true)

        ($script:SavedEntities | Where-Object { $_.RowKey -eq 'other-mcp' }) | Should -BeNullOrEmpty
    }

    It 'configures the saved client as an MCP OAuth client' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $true)

        Should -Invoke Set-CIPPMCPClientApp -Times 1 -Exactly -ParameterFilter { $AppId -eq 'new-app' }
    }

    It 'does not configure MCP when the saved client is not MCP-enabled' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $false)

        Should -Invoke Set-CIPPMCPClientApp -Times 0 -Exactly
    }
}

Describe 'Invoke-ExecApiClient - protected SSO/SAM apps' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippProtectedAppId -MockWith { @('sso-app', 'sam-app') }
        Mock -CommandName New-CIPPAPIConfig -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = 'sso-app'; AppName = 'CIPP-SSO'; Role = 'readonly' } }
    }

    It 'hides protected apps from the existing-app picker' {
        Mock -CommandName New-GraphGetRequest -MockWith { @([pscustomobject]@{ appId = 'sso-app' }, [pscustomobject]@{ appId = 'api-app' }) }
        $Request = [pscustomobject]@{ Headers = @{}; Query = [pscustomobject]@{ Action = 'ListAvailable' }; Body = $null }

        $Response = Invoke-ExecApiClient -Request $Request

        @($Response.Body.Results.appId) | Should -Be @('api-app')
    }

    It 'refuses to add a protected app as an existing client' {
        $Request = [pscustomobject]@{
            Headers = @{}
            Query   = [pscustomobject]@{ Action = 'AddUpdate' }
            Body    = [pscustomobject]@{ Action = 'AddUpdate'; ClientId = [pscustomobject]@{ value = 'sso-app' }; Role = [pscustomobject]@{ value = 'readonly' }; CIPPAPI = @{ ResetSecret = $true } }
        }

        $Response = Invoke-ExecApiClient -Request $Request

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-CIPPAPIConfig -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'refuses to reset the secret of a protected app' {
        $Request = [pscustomobject]@{ Headers = @{}; Query = [pscustomobject]@{ Action = 'ResetSecret' }; Body = [pscustomobject]@{ ClientId = 'sso-app' } }

        $Response = Invoke-ExecApiClient -Request $Request

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-CIPPAPIConfig -Times 0 -Exactly
    }
}

Describe 'Invoke-ExecApiClient - adopting an existing app registration' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippProtectedAppId -MockWith { @() }
        Mock -CommandName New-CIPPAPIConfig -MockWith { [pscustomobject]@{ ApplicationID = $script:AppId; AppName = 'Adopted'; Results = 'ok' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPSiteHostname -MockWith { @('https://cipp.contoso.com/.auth/login/aad/callback') }
        $script:AppId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $script:Request = [pscustomobject]@{
            Headers = @{}
            Query   = [pscustomobject]@{ Action = 'AddUpdate' }
            Params  = @{ CIPPEndpoint = 'ExecApiClient' }
            Body    = [pscustomobject]@{ Action = 'AddUpdate'; ClientId = [pscustomobject]@{ value = $script:AppId }; Role = [pscustomobject]@{ value = 'readonly' }; Enabled = $true; IpRange = [pscustomobject]@{ value = @() }; CIPPAPI = @{ ResetSecret = $true } }
        }
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'an app with no sign-in callback'; App = @{ signInAudience = 'AzureADMyOrg'; web = @{ redirectUris = @('https://other.example/callback') } } }
        @{ Name = 'an app whose callback belongs to another site'; App = @{ signInAudience = 'AzureADMyOrg'; web = @{ redirectUris = @('https://portal.fabrikam.com/.auth/login/aad/callback') } } }
        @{ Name = 'a multi-tenant app'; App = @{ signInAudience = 'AzureADMultipleOrgs'; web = @{ redirectUris = @('https://cipp.contoso.com/.auth/login/aad/callback') } } }
        @{ Name = 'an app that does not exist'; App = $null }
    ) {
        Mock -CommandName New-GraphGetRequest -MockWith { if ($App) { [pscustomobject]$App } }

        $Response = Invoke-ExecApiClient -Request $script:Request

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-CIPPAPIConfig -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'adopts an app that carries this site sign-in callback' {
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ signInAudience = 'AzureADMyOrg'; web = @{ redirectUris = @('https://old.example/x', 'https://cipp.contoso.com/.auth/login/aad/callback') } } }

        Invoke-ExecApiClient -Request $script:Request | Out-Null

        Should -Invoke New-CIPPAPIConfig -Times 1 -Exactly
    }

    It 'accepts any sign-in callback when the site hostnames are unknown' {
        Mock -CommandName Get-CIPPSiteHostname -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ signInAudience = 'AzureADMyOrg'; web = @{ redirectUris = @('https://whatever.example/.auth/login/aad/callback') } } }

        Invoke-ExecApiClient -Request $script:Request | Out-Null

        Should -Invoke New-CIPPAPIConfig -Times 1 -Exactly
    }

    It 'does not look the app up when it is already an API client' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = $script:AppId; PartitionKey = 'ApiClients'; AppName = 'Existing'; Role = 'readonly'; IPRange = '[]'; Enabled = $true; MCPAllowed = $false } }
        Mock -CommandName New-GraphGetRequest -MockWith { }

        Invoke-ExecApiClient -Request $script:Request | Out-Null

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke New-CIPPAPIConfig -Times 1 -Exactly
    }
}
