function Invoke-ExecMcp {
    <#
    .SYNOPSIS
        Model Context Protocol (MCP) server endpoint for CIPP.
    .DESCRIPTION
        A Streamable-HTTP MCP server running in JSON response mode (no SSE). It exposes
        CIPP's read-only API surface as MCP tools, projected at runtime from openapi.json.

        Every 'tools/call' is re-dispatched through New-CippCoreRequest using the caller's
        own principal headers, so the standard RBAC and tenant scoping in Test-CIPPAccess
        is enforced for each tool exactly as it would be for a normal API request. This
        endpoint's own role (CIPP.Core.Read) is only the floor required to use MCP at all.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # v1 supports HTTP POST (JSON response mode) only. SSE/GET streaming is not enabled.
    if ($Request.Method -and $Request.Method -ne 'POST') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::MethodNotAllowed
                Headers    = @{ 'Content-Type' = 'application/json'; 'Allow' = 'POST' }
                Body       = (@{ jsonrpc = '2.0'; id = $null; error = @{ code = -32600; message = 'Only HTTP POST (JSON mode) is supported.' } } | ConvertTo-Json -Compress)
            })
    }

    $CallerAppId = $Request.Headers.'x-ms-client-principal-name'
    $IsApiClient = $Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $CallerAppId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $McpAllowed = if ($IsApiClient) { [bool](Get-CippApiClient -AppId $CallerAppId).MCPAllowed } else { $true }
    if (-not $McpAllowed) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Headers    = @{ 'Content-Type' = 'application/json' }
                Body       = (@{ jsonrpc = '2.0'; id = $null; error = @{ code = -32001; message = 'This API client is not permitted to use the MCP server. Enable "MCP Access Allowed" on the API client in CIPP.' } } | ConvertTo-Json -Compress)
            })
    }

    $Rpc = $Request.Body

    # A JSON-RPC batch is an array. MCP removed batching in 2025-06-18, so refusing one is
    # correct - but it has to be refused, not accepted: the ids were merged into a single
    # call and the caller got back one reply carrying an array of ids, matching no request
    # it had sent.
    if ($Rpc -is [System.Collections.IList] -and $Rpc -isnot [string]) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Headers    = @{ 'Content-Type' = 'application/json' }
                Body       = (@{ jsonrpc = '2.0'; id = $null; error = @{ code = -32600; message = 'Batch requests are not supported; send one JSON-RPC request per call.' } } | ConvertTo-Json -Compress)
            })
    }

    $RpcId = $Rpc.id

    # JSON-RPC notifications carry no id and receive no response body. Body is set to an
    # empty string explicitly, because leaving it unset serialises as the four bytes 'null'.
    if ($null -eq $RpcId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Accepted; Body = '' })
    }

    try {
        if (-not $Rpc.method) {
            throw [pscustomobject]@{ code = -32600; message = 'Invalid Request: missing method' }
        }

        switch ($Rpc.method) {
            'initialize' {
                $Result = [ordered]@{
                    # Answer with a version this server actually speaks. Echoing whatever
                    # the client asked for meant a request for '1999-01-01' came back
                    # confirmed as agreed, and the client would then hold the server to a
                    # protocol it does not implement.
                    protocolVersion = $(
                        $Supported = @('2025-06-18', '2025-03-26', '2024-11-05')
                        $Wanted = [string]$Rpc.params.protocolVersion
                        if ($Wanted -and $Supported -contains $Wanted) { $Wanted } else { $Supported[0] }
                    )
                    capabilities    = @{ tools = @{ listChanged = $false } }
                    serverInfo      = [ordered]@{
                        name    = 'CIPP'
                        version = $Request.Headers.'X-CIPP-Version' ?? 'unknown'
                    }
                    instructions    = 'CIPP is a gateway to the read-only CIPP API. Seven tools are exposed: ListTenants (enumerate managed tenants; most tools need a tenantFilter — use the tenant''s defaultDomainName), ListGraphRequest (proxy an arbitrary Microsoft Graph GET), SearchTools (browse or keyword-search the full tool catalog), GetToolInfo (fetch a tool''s input schema), ExecTool (run any discovered tool by name), SearchDocs (search the CIPP documentation) and GetDoc (fetch one documentation page in full). Typical flow for data: ListTenants -> SearchTools -> GetToolInfo -> ExecTool. For questions about how CIPP works or how to configure it, start with SearchDocs rather than guessing.'
                }
            }
            'ping' { $Result = @{} }
            'tools/list' { $Result = [ordered]@{ tools = @(Get-CippMcpToolList -Request $Request) } }
            'tools/call' {
                $Result = Get-CippMcpToolResult -Request $Request -TriggerMetadata $TriggerMetadata -ToolName $Rpc.params.name -Arguments $Rpc.params.arguments
            }
            default { throw [pscustomobject]@{ code = -32601; message = "Method not found: $($Rpc.method)" } }
        }

        $ResponseBody = [ordered]@{ jsonrpc = '2.0'; id = $RpcId; result = $Result }
    } catch {
        $Code = $_.TargetObject.code ?? -32603
        $Message = $_.TargetObject.message ?? $_.Exception.Message
        $ResponseBody = [ordered]@{ jsonrpc = '2.0'; id = $RpcId; error = [ordered]@{ code = $Code; message = "$Message" } }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Headers    = @{ 'Content-Type' = 'application/json' }
            Body       = ($ResponseBody | ConvertTo-Json -Depth 30 -Compress)
        })
}
