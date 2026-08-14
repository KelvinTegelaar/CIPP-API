function Get-CippMcpToolResult {
    <#
    .SYNOPSIS
        Dispatches a single MCP 'tools/call' through the five-tool gateway.
    .DESCRIPTION
        SearchTools and GetToolInfo are answered locally from the read-only tool catalog, and
        SearchDocs / GetDoc from the documentation index shipped in the image.
        ListTenants, ListGraphRequest and ExecTool targets are re-dispatched through
        New-CippCoreRequest via Invoke-CippMcpApiRequest, so RBAC and tenant scoping are enforced
        on every execution. Direct calls to bare catalog tool names are still accepted for
        compatibility with clients configured before the five-tool gateway existed — the catalog
        remains the server-side allowlist either way. Returns an MCP tool result object
        ({ content, isError }). Not an HTTP entrypoint.
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

    $ArgHash = ConvertTo-CippMcpHashtable -InputObject $Arguments

    switch ($ToolName) {
        'SearchTools' {
            $Limit = $ArgHash['limit'] -as [int]
            if (-not $Limit) { $Limit = 25 }
            $SearchResult = Find-CippMcpTool -Request $Request -Query ([string]$ArgHash['query']) -Category ([string]$ArgHash['category']) -Limit $Limit
            return [ordered]@{
                content = @(@{ type = 'text'; text = ($SearchResult | ConvertTo-Json -Depth 10 -Compress) })
                isError = $false
            }
        }
        'GetToolInfo' {
            $MaxNames = 20
            $Requested = @(@($ArgHash['names'] ?? $ArgHash['name']) | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)
            $Names = @($Requested | Select-Object -First $MaxNames)
            # Past the cap the extra names were dropped without a word, so a caller asking
            # for 25 schemas got 20 back and no way to tell which five were missing.
            $Dropped = @($Requested | Select-Object -Skip $MaxNames)
            if ($Names.Count -eq 0) {
                throw [pscustomobject]@{ code = -32602; message = 'Invalid params: names (array of tool names from SearchTools) is required' }
            }
            $Catalog = @(Get-CippMcpToolCatalog -Request $Request)
            $Infos = [System.Collections.Generic.List[object]]::new()
            foreach ($Name in $Names) {
                $Candidates = @($Catalog | Where-Object { $_.name -eq $Name })
                $Entry = @($Candidates | Where-Object { $_._method -eq 'POST' })[0] ?? $Candidates[0]
                if ($Entry) {
                    $Infos.Add([ordered]@{
                            name        = $Entry.name
                            category    = $Entry._category
                            description = $Entry.description
                            inputSchema = $Entry.inputSchema
                        })
                } else {
                    $Infos.Add([ordered]@{ name = $Name; error = 'Unknown tool — find valid names with SearchTools.' })
                }
            }
            $InfoResult = [ordered]@{
                tools = @($Infos)
            }
            if ($Dropped.Count -gt 0) {
                $InfoResult['truncated'] = @($Dropped)
                $InfoResult['hint'] = "Only the first $MaxNames names were resolved; ask again for the rest, listed in truncated. Run a tool with ExecTool: { ""name"": ""<tool>"", ""arguments"": { ... } }."
            } else {
                $InfoResult['hint'] = 'Run a tool with ExecTool: { "name": "<tool>", "arguments": { ... } }.'
            }
            return [ordered]@{
                content = @(@{ type = 'text'; text = ($InfoResult | ConvertTo-Json -Depth 20 -Compress) })
                isError = $false
            }
        }
        'SearchDocs' {
            # Answered locally, like SearchTools: the documentation is shipped in the image and
            # is not tenant data, so there is nothing to re-dispatch through the API and no
            # tenant scoping to enforce.
            $Limit = $ArgHash['limit'] -as [int]
            if (-not $Limit) { $Limit = 8 }
            $DocResult = Find-CippDoc -Query ([string]$ArgHash['query']) -Path ([string]$ArgHash['path']) -Limit $Limit
            return [ordered]@{
                content = @(@{ type = 'text'; text = ($DocResult | ConvertTo-Json -Depth 10 -Compress) })
                isError = [bool]$DocResult.error
            }
        }
        'GetDoc' {
            $DocPath = [string]($ArgHash['path'] ?? $ArgHash['name'])
            if ([string]::IsNullOrWhiteSpace($DocPath)) {
                throw [pscustomobject]@{ code = -32602; message = 'Invalid params: path (from a SearchDocs result) is required' }
            }
            $Doc = Get-CippDoc -Path $DocPath
            return [ordered]@{
                content = @(@{ type = 'text'; text = ($Doc | ConvertTo-Json -Depth 10 -Compress) })
                isError = [bool]$Doc.error
            }
        }
        'ExecTool' {
            $TargetName = [string]$ArgHash['name']
            if ([string]::IsNullOrWhiteSpace($TargetName)) {
                throw [pscustomobject]@{ code = -32602; message = 'Invalid params: name (the tool to execute) is required' }
            }
            $Candidates = @(Get-CippMcpToolCatalog -Request $Request | Where-Object { $_.name -eq $TargetName })
            $Entry = @($Candidates | Where-Object { $_._method -eq 'POST' })[0] ?? $Candidates[0]
            if (-not $Entry) {
                # A wrong name here is a bad ARGUMENT to a valid tool, not an unknown tool,
                # so it comes back as a tool result the caller can act on rather than a
                # JSON-RPC error that reads as a transport failure. SearchTools' own scorer
                # supplies the alternatives: 'ListUser' is one character from 'ListUsers'
                # and the caller should be able to correct itself without a round trip.
                $Near = @((Find-CippMcpTool -Request $Request -Query $TargetName -Limit 5).tools | ForEach-Object { $_.name })
                $Hint = if ($Near.Count -gt 0) { " Did you mean: $($Near -join ', ')?" } else { ' Use SearchTools to discover valid tool names.' }
                return [ordered]@{
                    content = @(@{ type = 'text'; text = "No read-only tool named '$TargetName'.$Hint" })
                    isError = $true
                }
            }
            return Invoke-CippMcpApiRequest -Request $Request -TriggerMetadata $TriggerMetadata -ToolName $TargetName -Arguments $ArgHash['arguments'] -Method $Entry._method -ParamAlias $Entry._paramAlias
        }
        default {
            # Core passthroughs (always available) and legacy direct catalog calls (respect connector scoping).
            $Catalog = if ($ToolName -in @('ListTenants', 'ListGraphRequest')) {
                @(Get-CippMcpToolCatalog)
            } else {
                @(Get-CippMcpToolCatalog -Request $Request)
            }
            $Candidates = @($Catalog | Where-Object { $_.name -eq $ToolName })
            $Entry = @($Candidates | Where-Object { $_._method -eq 'POST' })[0] ?? $Candidates[0]
            if (-not $Entry) {
                throw [pscustomobject]@{ code = -32602; message = "Unknown or unavailable tool: $ToolName. Use SearchTools to discover valid tool names." }
            }
            return Invoke-CippMcpApiRequest -Request $Request -TriggerMetadata $TriggerMetadata -ToolName $ToolName -Arguments $Arguments -Method $Entry._method -ParamAlias $Entry._paramAlias
        }
    }
}
