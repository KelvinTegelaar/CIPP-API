function Get-CippMcpToolResult {
    <#
    .SYNOPSIS
        Executes a single MCP 'tools/call' by re-dispatching it through the CIPP API router.
    .DESCRIPTION
        Validates the requested tool against the read-only MCP tool list, then invokes the
        corresponding /api endpoint via New-CippCoreRequest using the caller's own principal
        headers. This guarantees Test-CIPPAccess (RBAC + tenant scoping + logging) runs for
        every tool call exactly as for a normal API request. The synthetic request is tagged
        with 'X-CIPP-Origin: mcp' so model-initiated calls are distinguishable in logs.
        Returns an MCP tool result object ({ content, isError }). Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata,
        [string]$ToolName,
        $Arguments
    )

    if ([string]::IsNullOrWhiteSpace($ToolName)) {
        throw [pscustomobject]@{ code = -32602; message = 'Invalid params: tool name is required' }
    }

    # The tool list is the read-only allowlist; anything not in it cannot be called.
    $Tool = Get-CippMcpToolList | Where-Object { $_.name -eq $ToolName } | Select-Object -First 1
    if (-not $Tool) {
        throw [pscustomobject]@{ code = -32602; message = "Unknown or unavailable tool: $ToolName" }
    }

    # Determine the HTTP method from the spec (defaults to GET for the read surface).
    $Spec = Get-CippMcpSpec
    $PathItem = $Spec['paths']["/api/$ToolName"]
    $Method = if ($PathItem -and $PathItem.Contains('post')) { 'POST' } else { 'GET' }

    # Flatten the MCP arguments object into a parameter hashtable. Arguments may arrive as a
    # dictionary or as a PSCustomObject depending on how the JSON-RPC body was deserialized.
    $ArgHash = @{}
    if ($Arguments -is [System.Collections.IDictionary]) {
        foreach ($Entry in $Arguments.GetEnumerator()) {
            $ArgHash[$Entry.Key] = $Entry.Value
        }
    } elseif ($Arguments) {
        foreach ($Prop in $Arguments.PSObject.Properties) {
            $ArgHash[$Prop.Name] = $Prop.Value
        }
    }

    # Clone caller headers (preserves the EasyAuth principal) and tag the origin for auditing.
    # The Functions worker exposes Headers as Dictionary[string,string]; PSObject.Properties on a
    # dictionary yields .NET members (Count, Keys, ...) rather than entries, dropping every header.
    $Headers = @{}
    if ($Request.Headers -is [System.Collections.IDictionary]) {
        foreach ($Entry in $Request.Headers.GetEnumerator()) {
            $Headers[$Entry.Key] = $Entry.Value
        }
    } elseif ($Request.Headers) {
        foreach ($Header in $Request.Headers.PSObject.Properties) {
            $Headers[$Header.Name] = $Header.Value
        }
    }
    $Headers['X-CIPP-Origin'] = 'mcp'

    $Query = @{}
    $Body = @{}
    if ($Method -eq 'GET') { $Query = $ArgHash } else { $Body = $ArgHash }

    $InnerRequest = [pscustomobject]@{
        Params  = @{ CIPPEndpoint = $ToolName }
        Method  = $Method
        Headers = $Headers
        Query   = $Query
        Body    = $Body
    }

    try {
        $Response = New-CippCoreRequest -Request $InnerRequest -TriggerMetadata $TriggerMetadata
    } catch {
        return [ordered]@{
            content = @(@{ type = 'text'; text = "Tool execution failed: $($_.Exception.Message)" })
            isError = $true
        }
    }

    $ResultBody = $Response.Body
    $Text = if ($ResultBody -is [string]) { $ResultBody } else { $ResultBody | ConvertTo-Json -Depth 20 -Compress }
    $IsError = $null -ne $Response.StatusCode -and [int]$Response.StatusCode -ge 400

    return [ordered]@{
        content = @(@{ type = 'text'; text = "$Text" })
        isError = $IsError
    }
}
