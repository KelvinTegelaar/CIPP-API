function Get-CippMcpToolList {
    <#
    .SYNOPSIS
        Projects the CIPP OpenAPI spec into the read-only MCP tool list, with optional per-connection filtering.
    .DESCRIPTION
        Returns every operation whose x-cipp-role ends in '.Read' (never '.ReadWrite') as an
        MCP tool definition: name (the API endpoint), description, inputSchema (JSON Schema
        built from the operation's query parameters / request body with $ref inlined), and
        read-only annotations. The full projection is cached per worker; pass -Force to rebuild.

        The connector URL's query string filters what is advertised (the query is NOT part of the
        OAuth resource, so it does not affect auth). One CIPP instance can therefore back several
        connector instances, each scoped to a subset. Supported query parameters:
          ?tags=Identity,Exchange     only tools in those top-level CIPP categories (the OpenAPI tag)
          ?tools=ListUsers,ListGroups explicit allow-list of tool names
          ?first=70 / ?limit=70       cap the number of tools (e.g. for clients with a tool ceiling)
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Request,
        [switch]$Force
    )

    # Build (and cache) the full read-only tool list. Each cached entry carries an internal _category
    # (top-level OpenAPI tag) used only for filtering; it is stripped before the list is returned.
    if (-not $script:CippMcpToolListCache -or $Force) {
        $Spec = Get-CippMcpSpec
        $Tools = [System.Collections.Generic.List[object]]::new()

        foreach ($PathEntry in $Spec['paths'].GetEnumerator()) {
            $Endpoint = $PathEntry.Key -replace '^/api/', ''

            # Never expose the MCP transport itself as a tool.
            if ($Endpoint -eq 'ExecMcp') { continue }

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
                    if ($Param['in'] -notin @('query', 'path')) { continue }
                    $Schema = if ($Param['schema']) { $Param['schema'] } else { @{ type = 'string' } }
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

                $InputSchema = [ordered]@{
                    type       = 'object'
                    properties = $Properties
                }
                if ($RequiredList.Count -gt 0) {
                    $InputSchema['required'] = @($RequiredList | Select-Object -Unique)
                }

                $Tag = @($Op['tags'])[0]
                $Category = if ($Tag) { ([string]$Tag -split '\s*>\s*')[0].Trim() } else { 'Uncategorized' }

                $Tools.Add([ordered]@{
                        name        = $Endpoint
                        description = Get-CippMcpDescription -Operation $Op
                        inputSchema = $InputSchema
                        annotations = [ordered]@{ title = $Endpoint; readOnlyHint = $true }
                        _category   = $Category
                    })
            }
        }

        $script:CippMcpToolListCache = $Tools
    }

    $Filtered = @($script:CippMcpToolListCache)

    # Per-connection filtering from the connector URL's query string.
    $Query = $Request.Query
    $TagFilter = "$($Query.tags ?? $Query.category ?? $Query.tag)".Trim()
    if ($TagFilter) {
        $WantedCats = @($TagFilter -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
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

    Write-Information "[MCP] tools/list -> $($Filtered.Count) tools (tags='$TagFilter' tools='$ToolFilter' first='$Limit')"

    # Project to the wire shape (drop the internal _category).
    return @($Filtered | ForEach-Object {
            [ordered]@{
                name        = $_.name
                description = $_.description
                inputSchema = $_.inputSchema
                annotations = $_.annotations
            }
        })
}

function Resolve-CippMcpNode {
    # Deep-resolves a parsed OpenAPI node (hashtable/array/scalar), inlining any $ref. Internal helper.
    param($Node, $Spec, [int]$Depth = 0, [string[]]$Seen = @())

    if ($null -eq $Node) { return $null }
    if ($Depth -gt 15) { return @{ type = 'object' } }
    if ($Node -is [string] -or $Node -is [valuetype]) { return $Node }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains('$ref')) {
            $Ref = [string]$Node['$ref']
            if ($Seen -contains $Ref) { return [ordered]@{ type = 'object'; description = 'recursive reference omitted' } }
            $Target = Resolve-CippMcpRef -Ref $Ref -Spec $Spec
            return Resolve-CippMcpNode -Node $Target -Spec $Spec -Depth ($Depth + 1) -Seen ($Seen + $Ref)
        }
        $Out = [ordered]@{}
        foreach ($Entry in $Node.GetEnumerator()) {
            if ($Entry.Key -eq '$ref') { continue }
            $Out[[string]$Entry.Key] = Resolve-CippMcpNode -Node $Entry.Value -Spec $Spec -Depth ($Depth + 1) -Seen $Seen
        }
        return $Out
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        return @($Node | ForEach-Object { Resolve-CippMcpNode -Node $_ -Spec $Spec -Depth ($Depth + 1) -Seen $Seen })
    }

    return $Node
}

function Resolve-CippMcpRef {
    # Resolves a JSON pointer like '#/components/parameters/tenantFilter' against the spec. Internal helper.
    param([string]$Ref, $Spec)

    $Segments = $Ref.TrimStart('#') -split '/' | Where-Object { $_ -ne '' }
    $Node = $Spec
    foreach ($Seg in $Segments) {
        $Key = $Seg -replace '~1', '/' -replace '~0', '~'
        if ($Node -is [System.Collections.IDictionary] -and $Node.Contains($Key)) {
            $Node = $Node[$Key]
        } else {
            return $null
        }
    }
    return $Node
}

function Get-CippMcpDescription {
    # Cleans the operation description (strips leaked PowerShell help) and prefixes the tag. Internal helper.
    param($Operation)

    $Desc = [string]$Operation['description']
    $Desc = $Desc -replace '(?s)\s*#>.*$', ''
    $Desc = $Desc -replace '(?s)\[CmdletBinding.*$', ''
    $Desc = $Desc.Trim()
    if ([string]::IsNullOrWhiteSpace($Desc)) { $Desc = [string]$Operation['summary'] }

    $Tag = @($Operation['tags'])[0]
    if ($Tag -and $Tag -ne 'Uncategorized') { $Desc = "[$Tag] $Desc" }
    return $Desc
}
