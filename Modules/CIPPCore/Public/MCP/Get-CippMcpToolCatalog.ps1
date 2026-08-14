function Get-CippMcpToolCatalog {
    <#
    .SYNOPSIS
        Projects the CIPP OpenAPI spec into the full read-only tool catalog, with optional per-connection filtering.
    .DESCRIPTION
        Returns every operation whose x-cipp-role ends in '.Read' (never '.ReadWrite') as a catalog
        entry: name (the API endpoint), description, inputSchema (JSON Schema built from the
        operation's query parameters / request body with $ref inlined), read-only annotations, and
        internal routing fields (_category, _method, _summary). The projection is cached per worker;
        pass -Force to rebuild.

        The catalog is NOT advertised to MCP clients wholesale — Get-CippMcpToolList exposes a fixed
        five-tool gateway, and this catalog backs its SearchTools / GetToolInfo / ExecTool tools.

        The connector URL's query string filters the catalog (the query is NOT part of the OAuth
        resource, so it does not affect auth). One CIPP instance can therefore back several
        connector instances, each scoped to a subset. Supported query parameters:
          ?tags=Identity,Exchange     only tools in those top-level CIPP categories (the OpenAPI tag)
          ?tools=ListUsers,ListGroups explicit allow-list of tool names
          ?first=70 / ?limit=70       cap the catalog size
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Request,
        [switch]$Force
    )

    if (-not $script:CippMcpToolCatalogCache -or $Force) {
        $Spec = Get-CippMcpSpec
        $Tools = [System.Collections.Generic.List[object]]::new()

        foreach ($PathEntry in $Spec['paths'].GetEnumerator()) {
            $Endpoint = $PathEntry.Key -replace '^/api/', ''

            # Never expose the MCP transport itself as a tool, nor the spec endpoint that
            # backs the in-app documentation browser: it returns the whole ~1.5 MB OpenAPI
            # document, which would flood the caller's context to tell it what SearchTools
            # already answers.
            #
            # ListCippDocs is excluded for a different reason: it is already advertised as the
            # SearchDocs and GetDoc core tools, and leaving it in the catalog would offer a
            # third name for the same thing with a different argument shape.
            if ($Endpoint -in @('ExecMcp', 'ListOpenApiSpec', 'ListCippDocs')) { continue }

            foreach ($MethodEntry in $PathEntry.Value.GetEnumerator()) {
                $Method = [string]$MethodEntry.Key
                if ($Method -notin @('get', 'post')) { continue }

                $Op = $MethodEntry.Value
                $Role = $Op['x-cipp-role']

                # Read-only surface only.
                if (-not $Role -or $Role -notmatch '\.Read$') { continue }

                # Defensive backstop: never expose an endpoint whose name implies a mutation,
                # even if its x-cipp-role is mislabeled '.Read' (e.g. AddTestReport, EditIntunePolicy).
                if ($Endpoint -match '^(Add|Set|Remove|Delete|Edit|New|Update|Disable|Enable|Reset|Revoke|Push|Clear|Start|Stop|Rename|Move|Copy)') { continue }

                $Properties = [ordered]@{}
                $RequiredList = [System.Collections.Generic.List[string]]::new()

                # Query / path parameters.
                foreach ($ParamRaw in @($Op['parameters'])) {
                    if (-not $ParamRaw) { continue }
                    $Param = Resolve-CippMcpNode -Node $ParamRaw -Spec $Spec
                    # a $ref that resolves to nothing yields $null; indexing it would throw
                    # and take the whole catalog down over one bad parameter
                    if ($Param -isnot [System.Collections.IDictionary]) { continue }
                    if ($Param['in'] -notin @('query', 'path')) { continue }
                    $Schema = if ($Param['schema']) { $Param['schema'] } else { @{ type = 'string' } }

                    # In OpenAPI a query parameter's description sits on the parameter, not on
                    # its schema - and only the schema was being kept, so every one of them was
                    # dropped on the way to the tool definition. That is the difference between
                    # a caller knowing that ListGraphRequest's $top is a page size rather than a
                    # result limit and having to discover it by getting the wrong answer. Copied
                    # onto the schema, which is the only place an MCP inputSchema can carry it.
                    if ($Param['description'] -and -not $Schema['description']) {
                        $Schema = [ordered]@{} + $Schema
                        $Schema['description'] = [string]$Param['description']
                    }

                    $Properties[[string]$Param['name']] = $Schema
                    if ($Param['required']) { $RequiredList.Add([string]$Param['name']) }
                }

                # Request body (uncommon for reads; included for completeness).
                if ($Op['requestBody'] -and $Op['requestBody']['content'] -and $Op['requestBody']['content']['application/json']) {
                    $BodySchema = Resolve-CippMcpNode -Node $Op['requestBody']['content']['application/json']['schema'] -Spec $Spec
                    if ($BodySchema -and $BodySchema['properties']) {
                        foreach ($BodyProp in $BodySchema['properties'].GetEnumerator()) {
                            $Properties[[string]$BodyProp.Key] = $BodyProp.Value
                        }
                        foreach ($Req in @($BodySchema['required'])) { if ($Req) { $RequiredList.Add([string]$Req) } }
                    }
                }

                # MCP property names must match ^[a-zA-Z0-9_.-]{1,64}$. CIPP endpoints read OData
                # system query options straight off the request - $Request.Query.'$filter',
                # '$select', '$top' - so those names arrive here with a leading $ and the client
                # rejects the request outright. It is not contained to the offending tool: any
                # schema carrying one is refused, which for ListGraphRequest (advertised directly
                # by Get-CippMcpToolList) means the gateway stops working. Rename for the wire and
                # keep a map so Invoke-CippMcpApiRequest can restore the real name on dispatch.
                $SafeProperties = [ordered]@{}
                $ParamAlias = @{}
                foreach ($Entry in $Properties.GetEnumerator()) {
                    $Safe = Get-CippMcpSafePropertyName -Name $Entry.Key -Taken $SafeProperties.Keys
                    if (-not $Safe) {
                        Write-Information "[MCP] $Endpoint : dropped unrepresentable parameter '$($Entry.Key)'"
                        continue
                    }
                    $SafeProperties[$Safe] = $Entry.Value
                    if ($Safe -ne $Entry.Key) { $ParamAlias[$Safe] = [string]$Entry.Key }
                }

                $InputSchema = [ordered]@{
                    type       = 'object'
                    properties = $SafeProperties
                }
                if ($RequiredList.Count -gt 0) {
                    # a renamed parameter must be required under the name the client will send
                    $SafeRequired = foreach ($Req in ($RequiredList | Select-Object -Unique)) {
                        $Mapped = $ParamAlias.GetEnumerator() | Where-Object { $_.Value -eq $Req } | Select-Object -First 1
                        if ($Mapped) { $Mapped.Key } elseif ($SafeProperties.Contains($Req)) { $Req }
                    }
                    $SafeRequired = @($SafeRequired | Where-Object { $_ })
                    if ($SafeRequired.Count -gt 0) { $InputSchema['required'] = $SafeRequired }
                }

                $Tag = @($Op['tags'])[0]
                $Category = if ($Tag) { ([string]$Tag -split '\s*>\s*')[0].Trim() } else { 'Uncategorized' }

                $Description = Get-CippMcpDescription -Operation $Op

                # Compact one-liner used by SearchTools results (schema-free, token-cheap).
                #
                # The spec's summary is only useful when it says something. build-openapi.ps1
                # emits `summary = $Contract.Synopsis ?? $Contract.Name`, and almost no
                # entrypoint carries a .SYNOPSIS, so 253 of 265 summaries were just the tool
                # name repeated - SearchTools results read "ListUsers: ListUsers" and the
                # caller had to spend a GetToolInfo call to learn anything. The descriptions
                # are there and are good, so fall back to the first line of one whenever the
                # summary carries no information beyond the name.
                $Summary = [string]$Op['summary']
                if ([string]::IsNullOrWhiteSpace($Summary) -or $Summary -eq $Endpoint) {
                    $Summary = (($Description -replace '^\[[^\]]+\]\s*', '') -split "\r?\n")[0].Trim()
                }
                if ($Summary.Length -gt 160) { $Summary = $Summary.Substring(0, 157) + '...' }

                $Tools.Add([ordered]@{
                        name        = $Endpoint
                        description = $Description
                        inputSchema = $InputSchema
                        annotations = [ordered]@{ title = $Endpoint; readOnlyHint = $true }
                        _category   = $Category
                        _method     = $Method.ToUpper()
                        _summary    = $Summary
                        _paramAlias = $ParamAlias
                    })
            }
        }

        $script:CippMcpToolCatalogCache = $Tools
    }

    $Filtered = @($script:CippMcpToolCatalogCache)

    # Per-connection filtering from the connector URL's query string.
    $Query = $Request.Query
    $TagFilter = "$($Query.tags ?? $Query.category ?? $Query.tag)".Trim()
    if ($TagFilter) {
        $WantedCats = @($TagFilter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        # A misspelt tag matched nothing and left an empty catalog, so the connector came up
        # advertising "0 read-only CIPP tools" with no indication why. Say which tag was not
        # recognised, in the log the operator will actually look at when that happens.
        $Known = @($Filtered | ForEach-Object { [string]$_._category } | Sort-Object -Unique)
        $Unknown = @($WantedCats | Where-Object { $_ -notin $Known })
        if ($Unknown.Count -gt 0) {
            Write-Warning "[MCP] Unknown connector tag(s): $($Unknown -join ', '). Known categories: $($Known -join ', ')."
        }
        $Filtered = @($Filtered | Where-Object { $_._category -in $WantedCats })
    }

    $ToolFilter = "$($Query.tools)".Trim()
    if ($ToolFilter) {
        $WantedTools = @($ToolFilter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $Filtered = @($Filtered | Where-Object { $_.name -in $WantedTools })
    }

    $Limit = ($Query.first ?? $Query.limit) -as [int]
    if ($Limit -gt 0) {
        $Filtered = @($Filtered | Select-Object -First $Limit)
    }

    return $Filtered
}
