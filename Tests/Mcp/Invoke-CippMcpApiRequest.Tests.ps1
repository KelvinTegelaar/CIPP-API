# Pester tests for the MCP tool-result normalisation (Invoke-CippMcpApiRequest).
#
# CIPP endpoints answer in three shapes -- a bare array, a { Results, Metadata } envelope,
# or a single object -- and nothing in the generated tool contract says which one a given
# tool uses. The MCP boundary is where that is reconciled, so these tests pin the rules:
# an envelope is unwrapped, anything else is passed through byte-for-byte, and the paging
# cursor in Metadata survives as its own content block instead of being dropped.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $McpRoot = Join-Path $BackendRoot 'Modules/CIPPCore/Public/MCP'
    foreach ($Leaf in 'ConvertTo-CippMcpHashtable.ps1', 'ConvertTo-CippMcpArgumentShape.ps1', 'Invoke-CippMcpApiRequest.ps1') {
        . (Join-Path $McpRoot $Leaf)
    }

    # The router is stubbed: these tests are about how a response is shaped for the model,
    # not about routing, RBAC or the endpoint behind it. The request it receives is captured so
    # the argument-shaping tests can assert what the endpoint would have seen.
    function New-CippCoreRequest {
        param($Request, $TriggerMetadata)
        $script:CapturedRequest = $Request
        return $script:StubResponse
    }

    function Invoke-ToolResult {
        param($Body, $StatusCode = 200)
        $script:StubResponse = [pscustomobject]@{ Body = $Body; StatusCode = $StatusCode }
        return Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThings' -Arguments @{}
    }

    # Dispatches with a schema and returns the request the router would have received, so a test
    # can inspect the coerced Query/Body the endpoint sees.
    function Get-DispatchedRequest {
        param($Arguments, $InputSchema, $Method = 'GET')
        $script:StubResponse = [pscustomobject]@{ Body = @(); StatusCode = 200 }
        $script:CapturedRequest = $null
        $null = Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThings' -Arguments $Arguments -Method $Method -InputSchema $InputSchema
        return $script:CapturedRequest
    }
}

Describe 'MCP tool result normalisation' {

    Context 'a { Results, Metadata } envelope' {
        It 'unwraps to the payload so the data is at the top level' {
            $Result = Invoke-ToolResult -Body @{ Results = @(@{ id = 1 }, @{ id = 2 }); Metadata = $null }
            $Payload = $Result.content[0].text | ConvertFrom-Json
            @($Payload).Count | Should -Be 2
            $Payload[0].id | Should -Be 1
            # the envelope itself must be gone, not merely reordered
            $Result.content[0].text | Should -Not -Match 'Results'
        }

        It 'unwraps the singular Result key too' {
            $Result = Invoke-ToolResult -Body @{ Result = 'Successfully did the thing' }
            $Result.content[0].text | Should -Be 'Successfully did the thing'
        }

        It 'emits no metadata block when Metadata is null' {
            $Result = Invoke-ToolResult -Body @{ Results = @(1, 2); Metadata = $null }
            @($Result.content).Count | Should -Be 1
        }

        It 'emits no metadata block when Metadata is an empty object' {
            $Result = Invoke-ToolResult -Body @{ Results = @(1, 2); Metadata = @{} }
            @($Result.content).Count | Should -Be 1
        }

        It 'returns a non-empty Metadata as a second content block, preserving nextLink' {
            $Result = Invoke-ToolResult -Body @{
                Results  = @(@{ id = 1 })
                Metadata = @{ nextLink = 'https://example.test/next?page=2' }
            }
            @($Result.content).Count | Should -Be 2
            $Result.content[1].text | Should -Match 'nextLink'
            $Result.content[1].text | Should -Match 'page=2'
            # the payload block stays clean - metadata must not be merged back in
            $Result.content[0].text | Should -Not -Match 'nextLink'
        }

        It 'unwraps a PSCustomObject envelope as well as a hashtable one' {
            $Result = Invoke-ToolResult -Body ([pscustomobject]@{ Results = @(@{ id = 7 }) })
            ($Result.content[0].text | ConvertFrom-Json)[0].id | Should -Be 7
        }
    }

    Context 'shapes that must be passed through untouched' {
        It 'leaves a bare array alone' {
            $Result = Invoke-ToolResult -Body @(@{ displayName = 'Group A' }, @{ displayName = 'Group B' })
            $Payload = $Result.content[0].text | ConvertFrom-Json
            @($Payload).Count | Should -Be 2
            $Payload[1].displayName | Should -Be 'Group B'
        }

        It 'leaves a single object alone' {
            $Result = Invoke-ToolResult -Body ([pscustomobject]@{ id = 'contoso.com'; isDefault = $true })
            $Payload = $Result.content[0].text | ConvertFrom-Json
            $Payload.id | Should -Be 'contoso.com'
            $Payload.isDefault | Should -BeTrue
        }

        It 'leaves a plain string alone' {
            $Result = Invoke-ToolResult -Body 'just a string'
            $Result.content[0].text | Should -Be 'just a string'
        }

        It 'does NOT unwrap an object carrying other keys alongside Results' {
            # unwrapping here would silently discard Severity
            $Result = Invoke-ToolResult -Body @{ Results = 'done'; Severity = 'Warn' }
            $Payload = $Result.content[0].text | ConvertFrom-Json
            $Payload.Results | Should -Be 'done'
            $Payload.Severity | Should -Be 'Warn'
        }
    }

    Context 'array shape survives the row count' {
        # PowerShell's pipeline unrolls a collection, so `$Body | ConvertTo-Json` turns a
        # one-row array into a bare object and an empty one into an empty string. The same
        # tool then changes JSON type with the number of rows it happens to find, which no
        # caller can parse reliably.
        It 'keeps a single-row result an array' {
            $Result = Invoke-ToolResult -Body @(@{ id = 'only' })
            $Result.content[0].text | Should -BeLike '`[*`]'
            @($Result.content[0].text | ConvertFrom-Json).Count | Should -Be 1
        }

        It 'keeps an empty result an empty array, not an empty string' {
            $Result = Invoke-ToolResult -Body @()
            $Result.content[0].text | Should -Be '[]'
        }

        It 'keeps a multi-row result an array' {
            $Result = Invoke-ToolResult -Body @(@{ id = 1 }, @{ id = 2 })
            @($Result.content[0].text | ConvertFrom-Json).Count | Should -Be 2
        }

        It 'keeps a single-row Results envelope an array once unwrapped' {
            $Result = Invoke-ToolResult -Body @{ Results = @(@{ id = 'only' }) }
            $Result.content[0].text | Should -BeLike '`[*`]'
        }
    }

    Context 'errors' {
        It 'keeps the envelope on an error so the message survives' {
            $Result = Invoke-ToolResult -Body @{ Results = "The 'Action' parameter is required." } -StatusCode 400
            $Result.isError | Should -BeTrue
            $Result.content[0].text | Should -Match 'Action'
        }

        It 'flags 4xx and 5xx as errors and 2xx as success' {
            (Invoke-ToolResult -Body @{ Results = 'x' } -StatusCode 500).isError | Should -BeTrue
            (Invoke-ToolResult -Body @{ Results = 'x' } -StatusCode 200).isError | Should -BeFalse
        }
    }
}

Describe 'MCP argument shaping (LabelValue coercion)' {
    # An autocomplete/select field is read by the endpoint as $Field.value, so the spec documents
    # it as a LabelValue object. A caller that sends a bare string used to reach the endpoint
    # unchanged, .value resolved to $null, and a field that scopes the query silently dropped the
    # scope - an unscoped 200 instead of an error. The dispatch path now reshapes it to { value }.
    BeforeAll {
        $script:UserSchema = @{
            type       = 'object'
            properties = @{
                user = @{ type = 'object'; properties = @{ value = @{ type = 'string' }; label = @{ type = 'string' } }; required = @('value') }
            }
        }
        $script:UsersArraySchema = @{
            type       = 'object'
            properties = @{
                users = @{ type = 'array'; items = @{ type = 'object'; properties = @{ value = @{ type = 'string' } }; required = @('value') } }
            }
        }
    }

    It 'wraps a bare string for a LabelValue field into { value }, on a POST body' {
        $Request = Get-DispatchedRequest -Arguments @{ user = 'user@contoso.com' } -InputSchema $script:UserSchema -Method 'POST'
        $Request.Body.user | Should -BeOfType [hashtable]
        $Request.Body.user.value | Should -Be 'user@contoso.com'
    }

    It 'wraps a bare string for a LabelValue field into { value }, on a GET query' {
        $Request = Get-DispatchedRequest -Arguments @{ user = 'user@contoso.com' } -InputSchema $script:UserSchema -Method 'GET'
        $Request.Query.user.value | Should -Be 'user@contoso.com'
    }

    It 'leaves an already-correct { value } object untouched' {
        $Request = Get-DispatchedRequest -Arguments @{ user = @{ value = 'user@contoso.com'; label = 'User' } } -InputSchema $script:UserSchema -Method 'POST'
        $Request.Body.user.value | Should -Be 'user@contoso.com'
        $Request.Body.user.label | Should -Be 'User'
    }

    It 'wraps each bare string in an array-of-LabelValue field' {
        $Request = Get-DispatchedRequest -Arguments @{ users = @('a@contoso.com', 'b@contoso.com') } -InputSchema $script:UsersArraySchema -Method 'POST'
        @($Request.Body.users).Count | Should -Be 2
        $Request.Body.users[0].value | Should -Be 'a@contoso.com'
        $Request.Body.users[1].value | Should -Be 'b@contoso.com'
    }

    It 'wraps a single bare string into a one-element array for an array-of-LabelValue field' {
        $Request = Get-DispatchedRequest -Arguments @{ users = 'only@contoso.com' } -InputSchema $script:UsersArraySchema -Method 'POST'
        @($Request.Body.users).Count | Should -Be 1
        $Request.Body.users[0].value | Should -Be 'only@contoso.com'
    }

    It 'leaves a field the schema does not describe exactly as sent' {
        $Request = Get-DispatchedRequest -Arguments @{ tenantFilter = 'contoso.com' } -InputSchema $script:UserSchema -Method 'POST'
        $Request.Body.tenantFilter | Should -Be 'contoso.com'
    }

    It 'passes a bare string through when no schema is supplied (back-compat)' {
        $script:StubResponse = [pscustomobject]@{ Body = @(); StatusCode = 200 }
        $script:CapturedRequest = $null
        $null = Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThings' -Arguments @{ user = 'user@contoso.com' } -Method 'POST'
        $script:CapturedRequest.Body.user | Should -Be 'user@contoso.com'
    }
}
