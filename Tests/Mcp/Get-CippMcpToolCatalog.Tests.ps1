# Pester tests for the MCP tool projection (Get-CippMcpToolCatalog and its helpers).
#
# The MCP surface is generated, not written: openapi.json is the input and the tool
# list is a pure projection of it. That makes the projection rules load-bearing --
# a role filter that leaks, a $ref that fails to resolve, or two operations on one
# path all turn into a wrong or dangerous tool contract in production. These tests
# pin the rules against hand-built specs, and the companion Spec.Tests.ps1 checks
# the real committed spec still satisfies them.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # The projection lives in Get-CippMcpToolCatalog; Get-CippMcpToolList is now just the
    # fixed five-tool gateway that sits in front of it.
    $McpRoot = Join-Path $BackendRoot 'Modules/CIPPCore/Public/MCP'
    if (-not (Test-Path $McpRoot)) { throw "Could not locate the MCP module at $McpRoot" }
    foreach ($Leaf in 'Resolve-CippMcpRef.ps1', 'Resolve-CippMcpNode.ps1', 'Get-CippMcpDescription.ps1', 'Get-CippMcpSafePropertyName.ps1', 'Get-CippMcpToolCatalog.ps1') {
        . (Join-Path $McpRoot $Leaf)
    }

    # Get-CippMcpSpec reads $env:CIPPRootPath at runtime; the projection only needs a
    # parsed document, so it is stubbed per-test with whatever fixture is in play.
    function Get-CippMcpSpec { return $script:FixtureSpec }

    function Get-OperationFixture {
        param(
            [string]$Role = 'Identity.User.Read',
            [string]$Tag = 'Identity > Administration',
            [string]$Description = 'Does a thing.',
            $Parameters,
            $RequestBody
        )
        $Operation = [ordered]@{
            'x-cipp-role' = $Role
            tags          = @($Tag)
            description   = $Description
            responses     = @{ '200' = @{ description = 'Success' } }
        }
        if ($Parameters) { $Operation['parameters'] = $Parameters }
        if ($RequestBody) { $Operation['requestBody'] = $RequestBody }
        return $Operation
    }

    function Initialize-FixtureSpec {
        param([hashtable]$Paths, [hashtable]$Components)
        $script:FixtureSpec = @{
            openapi    = '3.1.0'
            paths      = $Paths
            components = $Components ?? @{}
        }
        # the projection caches per worker; every fixture swap has to invalidate it
        $script:CippMcpToolCatalogCache = $null
    }

    function Get-ToolList {
        # the leading comma keeps a one-tool result an array; without it PowerShell
        # unrolls to the dictionary itself and [0]/.Count then read it as a map
        param([hashtable]$Query = @{})
        return , @(Get-CippMcpToolCatalog -Request ([pscustomobject]@{ Query = $Query }) -Force -InformationAction SilentlyContinue)
    }
}

Describe 'read-only surface' {
    It 'projects an operation whose role ends in .Read' {
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = (Get-OperationFixture -Role 'Identity.User.Read') } }
        (Get-ToolList).name | Should -Be 'ListUsers'
    }

    It 'excludes a ReadWrite role' {
        Initialize-FixtureSpec -Paths @{ '/api/ExecThing' = @{ post = (Get-OperationFixture -Role 'Identity.User.ReadWrite') } }
        Get-ToolList | Should -BeNullOrEmpty
    }

    It 'excludes an operation with no role at all' {
        $Operation = Get-OperationFixture
        $Operation.Remove('x-cipp-role')
        Initialize-FixtureSpec -Paths @{ '/api/ListUnroled' = @{ get = $Operation } }
        Get-ToolList | Should -BeNullOrEmpty
    }

    It 'never exposes the MCP transport itself' {
        Initialize-FixtureSpec -Paths @{ '/api/ExecMcp' = @{ post = (Get-OperationFixture -Role 'CIPP.AppSettings.Read') } }
        Get-ToolList | Should -BeNullOrEmpty
    }

    It 'excludes methods other than get and post' {
        Initialize-FixtureSpec -Paths @{ '/api/ListThings' = @{ delete = (Get-OperationFixture) } }
        Get-ToolList | Should -BeNullOrEmpty
    }

    # The backstop exists because a mislabeled .Read role on a mutating endpoint would
    # otherwise hand a model a write tool.
    It 'refuses a mutation-verb endpoint even when its role claims .Read' -ForEach @(
        'AddUser', 'SetThing', 'RemoveUser', 'DeleteThing', 'EditUser', 'NewThing',
        'UpdateThing', 'DisableUser', 'EnableUser', 'ResetPassword', 'RevokeSessions',
        'PushThing', 'ClearCache', 'StartJob', 'StopJob', 'RenameThing', 'MoveThing', 'CopyThing'
    ) {
        Initialize-FixtureSpec -Paths @{ "/api/$_" = @{ post = (Get-OperationFixture -Role 'Identity.User.Read') } }
        Get-ToolList | Should -BeNullOrEmpty
    }

    It 'does not mistake a List endpoint for a mutation' {
        Initialize-FixtureSpec -Paths @{ '/api/ListSettings' = @{ get = (Get-OperationFixture -Role 'CIPP.AppSettings.Read') } }
        (Get-ToolList).name | Should -Be 'ListSettings'
    }
}

Describe 'input schema' {
    It 'builds properties from query parameters' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{
                get = (Get-OperationFixture -Parameters @(
                        @{ name = 'tenantFilter'; 'in' = 'query'; required = $true; schema = @{ type = 'string' } }
                        @{ name = 'limit'; 'in' = 'query'; required = $false; schema = @{ type = 'integer' } }
                    ))
            }
        }
        $Tool = (Get-ToolList)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'tenantFilter'
        $Tool.inputSchema.properties['limit'].type | Should -Be 'integer'
        $Tool.inputSchema.required | Should -Be @('tenantFilter')
    }

    It 'ignores parameters that are not in query or path' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{
                get = (Get-OperationFixture -Parameters @(
                        @{ name = 'X-Custom'; 'in' = 'header'; schema = @{ type = 'string' } }
                    ))
            }
        }
        (Get-ToolList)[0].inputSchema.properties.Count | Should -Be 0
    }

    It 'defaults a parameter with no schema to string' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Parameters @(@{ name = 'q'; 'in' = 'query' })) }
        }
        (Get-ToolList)[0].inputSchema.properties['q'].type | Should -Be 'string'
    }

    It 'folds request body properties into the same input schema' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListThings' = @{
                post = (Get-OperationFixture -RequestBody @{
                        content = @{ 'application/json' = @{ schema = @{
                                    type       = 'object'
                                    properties = @{ tenantFilter = @{ type = 'string' }; name = @{ type = 'string' } }
                                    required   = @('tenantFilter')
                                }
                            }
                        }
                    })
            }
        }
        $Tool = (Get-ToolList)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'name'
        $Tool.inputSchema.required | Should -Contain 'tenantFilter'
    }

    It 'omits required entirely when nothing is required' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Parameters @(@{ name = 'q'; 'in' = 'query'; required = $false; schema = @{ type = 'string' } })) }
        }
        (Get-ToolList)[0].inputSchema.Contains('required') | Should -BeFalse
    }

    It 'does not repeat a name that appears in both query and body' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListThings' = @{
                post = (Get-OperationFixture `
                        -Parameters @(@{ name = 'tenantFilter'; 'in' = 'query'; required = $true; schema = @{ type = 'string' } }) `
                        -RequestBody @{ content = @{ 'application/json' = @{ schema = @{
                                    type = 'object'; properties = @{ tenantFilter = @{ type = 'string' } }; required = @('tenantFilter')
                                }
                            }
                        } })
            }
        }
        $Tool = (Get-ToolList)[0]
        @($Tool.inputSchema.required) | Should -Be @('tenantFilter')
    }
}

Describe '$ref resolution' {
    It 'inlines a component parameter $ref' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Parameters @(@{ '$ref' = '#/components/parameters/tenantFilter' })) }
        } -Components @{
            parameters = @{
                tenantFilter = @{ name = 'tenantFilter'; 'in' = 'query'; required = $true; schema = @{ type = 'string' } }
            }
        }
        $Tool = (Get-ToolList)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'tenantFilter'
        $Tool.inputSchema.required | Should -Be @('tenantFilter')
    }

    It 'inlines a schema $ref inside the request body' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListThings' = @{
                post = (Get-OperationFixture -RequestBody @{
                        content = @{ 'application/json' = @{ schema = @{ '$ref' = '#/components/schemas/Payload' } } }
                    })
            }
        } -Components @{
            schemas = @{ Payload = @{ type = 'object'; properties = @{ target = @{ '$ref' = '#/components/schemas/LabelValue' } } } }
        }
        $Tool = (Get-ToolList)[0]
        $Tool.inputSchema.properties.Keys | Should -Contain 'target'
    }

    It 'survives a recursive $ref instead of hanging' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListThings' = @{
                post = (Get-OperationFixture -RequestBody @{
                        content = @{ 'application/json' = @{ schema = @{ '$ref' = '#/components/schemas/Loop' } } }
                    })
            }
        } -Components @{
            schemas = @{ Loop = @{ type = 'object'; properties = @{ self = @{ '$ref' = '#/components/schemas/Loop' } } } }
        }
        { Get-ToolList } | Should -Not -Throw
    }

    It 'does not throw on a $ref that points at nothing' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Parameters @(@{ '$ref' = '#/components/parameters/missing' })) }
        } -Components @{ parameters = @{} }
        { Get-ToolList } | Should -Not -Throw
    }
}

Describe 'descriptions' {
    It 'prefixes the description with the operation tag' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Tag 'Identity > Administration' -Description 'Lists users.') }
        }
        (Get-ToolList)[0].description | Should -Be '[Identity > Administration] Lists users.'
    }

    It 'strips leaked PowerShell help out of a description' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture -Description "Lists users.`n    #>`n    [CmdletBinding()]") }
        }
        $Description = (Get-ToolList)[0].description
        $Description | Should -Not -Match '#>'
        $Description | Should -Not -Match 'CmdletBinding'
    }

    It 'falls back to the summary when there is no description' {
        $Operation = Get-OperationFixture -Description ''
        $Operation['summary'] = 'Summary text.'
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = $Operation } }
        (Get-ToolList)[0].description | Should -Match 'Summary text\.'
    }
}

Describe 'annotations' {
    It 'marks every projected tool read-only' {
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = (Get-OperationFixture) } }
        $Tool = (Get-ToolList)[0]
        $Tool.annotations.readOnlyHint | Should -BeTrue
        $Tool.annotations.title | Should -Be 'ListUsers'
    }

    It 'carries the internal routing fields for the gateway to use' {
        # The catalog is internal by design: SearchTools ranks on _category, ExecTool routes
        # on _method, and Invoke-CippMcpApiRequest reverses _paramAlias. Keeping these OFF the
        # wire is Get-CippMcpToolList's job and is asserted in McpGateway.Tests.ps1.
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = (Get-OperationFixture) } }
        $Keys = @((Get-ToolList)[0].Keys)
        $Keys | Should -Contain '_category'
        $Keys | Should -Contain '_method'
    }
}

Describe 'connection filtering' {
    BeforeEach {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers'    = @{ get = (Get-OperationFixture -Tag 'Identity > Administration') }
            '/api/ListGroups'   = @{ get = (Get-OperationFixture -Tag 'Identity > Administration') }
            '/api/ListMailboxes' = @{ get = (Get-OperationFixture -Tag 'Email > Administration') }
        }
    }

    It 'returns everything with no query' {
        (Get-ToolList).Count | Should -Be 3
    }

    It 'filters to a top-level category' {
        $Tools = Get-ToolList -Query @{ tags = 'Identity' }
        $Tools.Count | Should -Be 2
        $Tools.name | Should -Not -Contain 'ListMailboxes'
    }

    It 'accepts several categories' {
        (Get-ToolList -Query @{ tags = 'Identity,Email' }).Count | Should -Be 3
    }

    It 'accepts the tag and category aliases' {
        (Get-ToolList -Query @{ category = 'Email' }).Count | Should -Be 1
        (Get-ToolList -Query @{ tag = 'Email' }).Count | Should -Be 1
    }

    It 'filters to an explicit tool allow-list' {
        $Tools = Get-ToolList -Query @{ tools = 'ListUsers,ListMailboxes' }
        @($Tools.name | Sort-Object) | Should -Be @('ListMailboxes', 'ListUsers')
    }

    It 'caps the count for clients with a tool ceiling' {
        (Get-ToolList -Query @{ first = 2 }).Count | Should -Be 2
        (Get-ToolList -Query @{ limit = 1 }).Count | Should -Be 1
    }

    It 'combines a category filter with a cap' {
        (Get-ToolList -Query @{ tags = 'Identity'; first = 1 }).Count | Should -Be 1
    }

    It 'returns nothing for a category that matches nothing' {
        Get-ToolList -Query @{ tags = 'Nonexistent' } | Should -BeNullOrEmpty
    }

    It 'treats an untagged operation as Uncategorized' {
        $Operation = Get-OperationFixture
        $Operation.Remove('tags')
        Initialize-FixtureSpec -Paths @{ '/api/ListLoose' = @{ get = $Operation } }
        (Get-ToolList -Query @{ tags = 'Uncategorized' }).name | Should -Be 'ListLoose'
    }
}

Describe 'caching' {
    It 'reuses the cached projection until -Force' {
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = (Get-OperationFixture) } }
        (Get-ToolList).Count | Should -Be 1

        # swap the underlying spec without invalidating
        $script:FixtureSpec = @{
            openapi = '3.1.0'; components = @{}
            paths   = @{ '/api/ListUsers' = @{ get = (Get-OperationFixture) }; '/api/ListGroups' = @{ get = (Get-OperationFixture) } }
        }
        @(Get-CippMcpToolCatalog -Request ([pscustomobject]@{ Query = @{} }) -InformationAction SilentlyContinue).Count |
            Should -Be 1

        @(Get-CippMcpToolCatalog -Request ([pscustomobject]@{ Query = @{} }) -Force -InformationAction SilentlyContinue).Count |
            Should -Be 2
    }
}

Describe 'tool identity' {
    It 'names a tool after the endpoint, not the path' {
        Initialize-FixtureSpec -Paths @{ '/api/ListUsers' = @{ get = (Get-OperationFixture) } }
        (Get-ToolList)[0].name | Should -Be 'ListUsers'
    }

    # Get-CippMcpToolResult looks a tool up by name; duplicates would make the
    # resolution order decide which endpoint a model actually calls.
    It 'produces one tool per path even when a path carries two operations' {
        Initialize-FixtureSpec -Paths @{
            '/api/ListUsers' = @{ get = (Get-OperationFixture); post = (Get-OperationFixture) }
        }
        $Tools = Get-ToolList
        $Tools.Count | Should -Be 2
        # documents today's behaviour: the guard against this lives in the generator
        # and in Spec.Tests.ps1, not here
        @($Tools.name | Select-Object -Unique).Count | Should -Be 1
    }
}
