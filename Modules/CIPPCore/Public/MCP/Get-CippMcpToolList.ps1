function Get-CippMcpToolList {
    <#
    .SYNOPSIS
        Returns the fixed five-tool gateway advertised to MCP clients.
    .DESCRIPTION
        tools/list never dumps the full read-only catalog (200+ tool schemas would flood the
        client's context window). Instead every connection is offered the same five core tools:
          - ListTenants       direct passthrough; the entry point for tenant resolution
          - ListGraphRequest  direct passthrough; arbitrary Microsoft Graph GET proxy
          - SearchTools       browse/search the catalog (compact results, no schemas)
          - GetToolInfo       full description + inputSchema for named catalog tools
          - ExecTool          execute any catalog tool by name
        The connector URL's query filters (?tags=, ?tools=, ?first=) scope the catalog visible to
        SearchTools/GetToolInfo/ExecTool; the five core tools themselves are always advertised.
        Passthrough schemas are projected live from the catalog so they track openapi.json.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Request)

    # Unfiltered catalog: the core passthroughs are always available regardless of connector scoping.
    $Catalog = @(Get-CippMcpToolCatalog)
    $FilteredCount = @(Get-CippMcpToolCatalog -Request $Request | Group-Object -Property { $_.name }).Count

    $Tools = [System.Collections.Generic.List[object]]::new()

    $PassthroughNotes = @{
        ListTenants      = ' Start here: most CIPP tools require a tenantFilter — use the tenant''s defaultDomainName (or customerId for the GUID).'
        ListGraphRequest = ' Use this when no dedicated CIPP tool covers the data: pass Endpoint (e.g. "users" or "deviceManagement/managedDevices"), tenantFilter, and optionally graphFilter/expand/ListProperties.'
    }
    foreach ($CoreName in @('ListTenants', 'ListGraphRequest')) {
        $Candidates = @($Catalog | Where-Object { $_.name -eq $CoreName })
        $Entry = @($Candidates | Where-Object { $_._method -eq 'POST' })[0] ?? $Candidates[0]
        if (-not $Entry) { continue }
        $Tools.Add([ordered]@{
                name        = $Entry.name
                description = "$($Entry.description)$($PassthroughNotes[$CoreName])"
                inputSchema = $Entry.inputSchema
                annotations = $Entry.annotations
            })
    }

    $Tools.Add([ordered]@{
            name        = 'SearchTools'
            description = "Search and browse the catalog of $FilteredCount read-only CIPP tools. Call with no arguments for a category overview, with category to list a category's tools, or with query keywords for a ranked search. Results are compact (name, category, one-line summary). Follow up with GetToolInfo for a tool's input schema, then ExecTool to run it."
            inputSchema = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    query    = @{ type = 'string'; description = 'Keywords to search for across tool names and descriptions (e.g. "mailbox permissions").' }
                    category = @{ type = 'string'; description = 'Exact category name from the category overview (e.g. "Email-Exchange", "Identity").' }
                    limit    = @{ type = 'integer'; description = 'Maximum number of results (default 25, max 100).' }
                }
            }
            annotations = [ordered]@{ title = 'SearchTools'; readOnlyHint = $true }
        })

    $Tools.Add([ordered]@{
            name        = 'GetToolInfo'
            description = 'Get the full description and input schema (JSON Schema) for one or more CIPP tools found via SearchTools. Always check a tool''s schema here before running it with ExecTool.'
            inputSchema = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    names = @{ type = 'array'; items = @{ type = 'string' }; description = 'Tool names as returned by SearchTools (max 20 per call).' }
                }
                required   = @('names')
            }
            annotations = [ordered]@{ title = 'GetToolInfo'; readOnlyHint = $true }
        })

    $Tools.Add([ordered]@{
            name        = 'ExecTool'
            description = 'Execute any read-only CIPP tool by name. Discover tools with SearchTools and fetch their input schema with GetToolInfo first; RBAC and tenant scoping are enforced server-side on every call.'
            inputSchema = [ordered]@{
                type       = 'object'
                properties = [ordered]@{
                    name      = @{ type = 'string'; description = 'The tool name, exactly as returned by SearchTools/GetToolInfo.' }
                    arguments = @{ type = 'object'; description = 'Arguments matching the tool''s inputSchema from GetToolInfo. Omit if the tool needs no parameters.' }
                }
                required   = @('name')
            }
            annotations = [ordered]@{ title = 'ExecTool'; readOnlyHint = $true }
        })

    Write-Information "[MCP] tools/list -> $($Tools.Count) core tools (catalog=$FilteredCount)"

    return @($Tools)
}
