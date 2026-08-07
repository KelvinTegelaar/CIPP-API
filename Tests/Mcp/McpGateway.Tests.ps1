# Pester tests for the five-tool MCP gateway and the parameter-name rules it depends on.
#
# The gateway keeps ~260 tool schemas out of the client's context by advertising only
# ListTenants, ListGraphRequest, SearchTools, GetToolInfo and ExecTool. That makes the two
# advertised passthrough schemas load-bearing in a way the catalog entries are not: a
# catalog entry's schema only ever travels as text inside a GetToolInfo result, but
# ListGraphRequest's schema is a real tool definition sent to the model's API.
#
# MCP property names must match ^[a-zA-Z0-9_.-]{1,64}$, and CIPP endpoints read OData
# options straight off the request ($Request.Query.'$filter'), so ListGraphRequest arrives
# with eight '$'-prefixed names. Unsanitised, the API rejects the request outright and the
# gateway stops working entirely. These tests pin the rename and its reversal.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $McpRoot = Join-Path $BackendRoot 'Modules/CIPPCore/Public/MCP'
    foreach ($Leaf in 'Resolve-CippMcpRef.ps1', 'Resolve-CippMcpNode.ps1', 'Get-CippMcpDescription.ps1',
        'Get-CippMcpSafePropertyName.ps1', 'Get-CippMcpToolCatalog.ps1', 'Get-CippMcpToolList.ps1',
        'ConvertTo-CippMcpHashtable.ps1', 'Find-CippMcpTool.ps1', 'Invoke-CippMcpApiRequest.ps1') {
        . (Join-Path $McpRoot $Leaf)
    }

    function Get-CippMcpSpec { return $script:FixtureSpec }

    function Initialize-FixtureSpec {
        param([hashtable]$Paths)
        $script:FixtureSpec = @{ openapi = '3.1.0'; paths = $Paths; components = @{} }
        $script:CippMcpToolCatalogCache = $null
    }

    function New-ParamOperation {
        param([string[]]$Names, [string[]]$Required = @(), [string]$Tag = 'CIPP > Core')
        return [ordered]@{
            'x-cipp-role' = 'CIPP.Core.Read'
            tags          = @($Tag)
            description   = 'Takes OData options.'
            responses     = @{ '200' = @{ description = 'Success' } }
            parameters    = @(foreach ($N in $Names) {
                    @{ name = $N; in = 'query'; required = ($Required -contains $N); schema = @{ type = 'string' } }
                })
        }
    }

    function Get-Catalog { param([hashtable]$Query = @{})
        return , @(Get-CippMcpToolCatalog -Request ([pscustomobject]@{ Query = $Query }) -Force -InformationAction SilentlyContinue)
    }
}

Describe 'Get-CippMcpSafePropertyName' {

    It 'leaves an already-valid name alone' {
        Get-CippMcpSafePropertyName -Name 'tenantFilter' | Should -Be 'tenantFilter'
    }

    It 'prefixes an OData option rather than stripping the $' {
        Get-CippMcpSafePropertyName -Name '$filter' | Should -Be 'odata_filter'
    }

    It 'refuses to shadow a parameter the endpoint already has' {
        # ListGraphRequest really does take both '$expand' and 'expand'
        Get-CippMcpSafePropertyName -Name '$expand' -Taken @('odata_expand') | Should -BeNullOrEmpty
    }

    It 'replaces other illegal characters' {
        Get-CippMcpSafePropertyName -Name 'weird name!' | Should -Be 'weird_name_'
    }

    It 'always returns a name the client will accept' {
        foreach ($Name in '$filter', '$top', 'weird name!', 'a', 'ok_one', '$count') {
            $Safe = Get-CippMcpSafePropertyName -Name $Name
            if ($Safe) { $Safe | Should -Match '^[a-zA-Z0-9_.-]{1,64}$' }
        }
    }
}

Describe 'catalog parameter naming' {

    It 'renames an OData option and records the alias' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThing' = @{ get = (New-ParamOperation -Names '$filter', 'tenantFilter') } }
        $Tool = (Get-Catalog)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'odata_filter'
        $Tool.inputSchema.properties.Keys | Should -Not -Contain '$filter'
        $Tool._paramAlias['odata_filter'] | Should -Be '$filter'
    }

    It 'keeps $expand and expand as two distinct parameters' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThing' = @{ get = (New-ParamOperation -Names '$expand', 'expand') } }
        $Tool = (Get-Catalog)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'odata_expand'
        $Tool.inputSchema.properties.Keys | Should -Contain 'expand'
        @($Tool.inputSchema.properties.Keys).Count | Should -Be 2
    }

    It 'marks a renamed parameter required under its new name' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThing' = @{ get = (New-ParamOperation -Names '$filter' -Required '$filter') } }
        $Tool = (Get-Catalog)[0]
        $Tool.inputSchema.required | Should -Contain 'odata_filter'
        $Tool.inputSchema.required | Should -Not -Contain '$filter'
    }

    It 'never emits a property name the client would reject' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThing' = @{ get = (New-ParamOperation -Names '$filter', '$top', 'weird name!', 'ok_one') } }
        foreach ($Key in (Get-Catalog)[0].inputSchema.properties.Keys) {
            $Key | Should -Match '^[a-zA-Z0-9_.-]{1,64}$'
        }
    }
}

Describe 'the gateway advertised to clients' {

    BeforeAll {
        function Get-Gateway {
            Initialize-FixtureSpec -Paths @{
                '/api/ListTenants'      = @{ get = (New-ParamOperation -Names 'tenantFilter' -Tag 'Tenant > Administration') }
                '/api/ListGraphRequest' = @{ get = (New-ParamOperation -Names 'Endpoint', 'tenantFilter', '$filter', '$select', 'expand') }
                '/api/ListUsers'        = @{ get = (New-ParamOperation -Names 'tenantFilter' -Tag 'Identity > Administration') }
            }
            $null = Get-CippMcpToolCatalog -Force -InformationAction SilentlyContinue
            return , @(Get-CippMcpToolList -Request ([pscustomobject]@{ Query = @{} }))
        }
    }

    It 'advertises exactly the five gateway tools' {
        $Names = @((Get-Gateway).name)
        $Names | Should -Contain 'ListTenants'
        $Names | Should -Contain 'ListGraphRequest'
        $Names | Should -Contain 'SearchTools'
        $Names | Should -Contain 'GetToolInfo'
        $Names | Should -Contain 'ExecTool'
        # the catalog is reached through SearchTools, never advertised wholesale
        $Names | Should -Not -Contain 'ListUsers'
    }

    It 'advertises no property name the client would reject' {
        # the regression that took the whole gateway down: ListGraphRequest carries eight
        # '$'-prefixed OData options and its schema is a real tool definition
        $Offenders = foreach ($Tool in (Get-Gateway)) {
            foreach ($Key in $Tool.inputSchema.properties.Keys) {
                if ($Key -cnotmatch '^[a-zA-Z0-9_.-]{1,64}$') { "$($Tool.name).$Key" }
            }
        }
        @($Offenders) -join ', ' | Should -BeNullOrEmpty
    }

    It 'does not leak the internal alias map onto the wire' {
        foreach ($Tool in (Get-Gateway)) {
            @($Tool.Keys) | Should -Not -Contain '_paramAlias'
            @($Tool.Keys) | Should -Not -Contain '_category'
        }
    }
}

Describe 'dispatch restores the real parameter name' {

    BeforeAll {
        function New-CippCoreRequest { param($Request, $TriggerMetadata) $script:Captured = $Request; return [pscustomobject]@{ Body = @('ok'); StatusCode = 200 } }
    }

    It 'sends $filter to the endpoint when the client sent odata_filter' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThing' = @{ get = (New-ParamOperation -Names '$filter', 'tenantFilter') } }
        $Tool = (Get-Catalog)[0]
        $script:Captured = $null

        Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThing' `
            -Arguments @{ odata_filter = "displayName eq 'x'"; tenantFilter = 'contoso.com' } `
            -Method 'GET' -ParamAlias $Tool._paramAlias | Out-Null

        $script:Captured.Query['$filter'] | Should -Be "displayName eq 'x'"
        $script:Captured.Query.ContainsKey('odata_filter') | Should -BeFalse
        $script:Captured.Query['tenantFilter'] | Should -Be 'contoso.com'
    }

    It 'leaves arguments untouched when the tool has no aliases' {
        $script:Captured = $null
        Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThing' `
            -Arguments @{ tenantFilter = 'contoso.com' } -Method 'GET' -ParamAlias @{} | Out-Null
        $script:Captured.Query['tenantFilter'] | Should -Be 'contoso.com'
    }
}
