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
    foreach ($Leaf in 'ConvertTo-CippMcpHashtable.ps1', 'Invoke-CippMcpApiRequest.ps1') {
        . (Join-Path $McpRoot $Leaf)
    }

    # The router is stubbed: these tests are about how a response is shaped for the model,
    # not about routing, RBAC or the endpoint behind it.
    function New-CippCoreRequest { return $script:StubResponse }

    function Invoke-ToolResult {
        param($Body, $StatusCode = 200)
        $script:StubResponse = [pscustomobject]@{ Body = $Body; StatusCode = $StatusCode }
        return Invoke-CippMcpApiRequest -Request ([pscustomobject]@{ Headers = @{} }) -ToolName 'ListThings' -Arguments @{}
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
