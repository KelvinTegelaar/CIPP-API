# Pester tests for single-holder MCP enforcement in Invoke-ExecApiClient (AddUpdate).
#
# Issue #619: several API clients ended up with MCPAllowed set at once because each failed MCP setup
# left a record behind and nothing cleared the flag on the others. Only one client per instance may
# hold MCP Access, since the connector flow advertises exactly one app registration. Saving a client
# with MCP Access enabled must now clear the flag on every other client.

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
    function Set-CIPPMCPClientApp { param($AppId, $Headers) }
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

Describe 'Invoke-ExecApiClient - single MCP holder enforcement' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPMCPClientApp -MockWith { }

        # The new client's RowKey lookup finds nothing (it's new); the unfiltered roster scan returns
        # the two existing clients, one of which already (wrongly) holds MCP Access.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null } -ParameterFilter { $Filter -like 'RowKey eq*' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'other-mcp'; AppName = 'Stale'; Role = 'readonly'; MCPAllowed = $true; Enabled = $true }
                [pscustomobject]@{ PartitionKey = 'ApiClients'; RowKey = 'plain'; AppName = 'Plain'; Role = 'readonly'; MCPAllowed = $false; Enabled = $true }
            )
        } -ParameterFilter { -not $Filter }

        $script:SavedEntities = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            $script:SavedEntities.Add(($Entity | ConvertTo-Json -Depth 6 | ConvertFrom-Json))
        }
    }

    It 'clears MCP Access on other clients when saving an MCP-enabled client' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $true)

        $Cleared = $script:SavedEntities | Where-Object { $_.RowKey -eq 'other-mcp' }
        $Cleared | Should -Not -BeNullOrEmpty
        [bool]$Cleared.MCPAllowed | Should -BeFalse
    }

    It 'configures the saved client as the MCP resource app' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $true)

        Should -Invoke Set-CIPPMCPClientApp -Times 1 -Exactly -ParameterFilter { $AppId -eq 'new-app' }
    }

    It 'never rewrites the client that already had MCP Access disabled' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $true)

        ($script:SavedEntities | Where-Object { $_.RowKey -eq 'plain' }) | Should -BeNullOrEmpty
    }

    It 'leaves other clients alone when the saved client is not MCP-enabled' {
        $null = Invoke-ExecApiClient -Request (New-AddUpdateRequest -McpAllowed $false)

        ($script:SavedEntities | Where-Object { $_.RowKey -eq 'other-mcp' }) | Should -BeNullOrEmpty
        Should -Invoke Set-CIPPMCPClientApp -Times 0 -Exactly
    }
}
