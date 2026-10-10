# Pester tests for MCP client handling in Invoke-ExecApiClient (AddUpdate).
#
# Split-app model: an MCPAllowed API client is an OAuth *client* (the app a connector signs in as),
# and the dedicated CIPP-MCP app is the shared resource. Several MCPAllowed clients may coexist, each
# with its own role/IP/redirects/CA, so saving one must NOT clear MCP Access on the others. Enabling
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

    . $FunctionPath

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
