#Requires -Version 7.0
<#
.SYNOPSIS
    Enriches a CIPP openapi.json with typed 200 response schemas derived by static
    analysis of the API and frontend repositories.

.DESCRIPTION
    The generated CIPP spec types every request body but leaves every 200 response
    as the generic StandardResults envelope. This stage fills typed per-endpoint
    response schemas for the read surface, using two deterministic sources that are
    already checked into the repositories (no live API calls):

      1. Captured response shape baselines (CIPP/Tests/Shapes/*.json) - carry real
         field types and nesting. Preferred when present.
      2. Frontend table column declarations (simpleColumns in CIPP/src pages) -
         carry field names only. Used when no baseline exists; fields are typed as
         string and marked x-cipp-field-source: frontend so consumers know the type
         is a name-only inference, not a verified type.

    Endpoints with neither source keep the StandardResults envelope, which is the
    correct shape for write/exec operations. Output is deterministic: the same input
    repositories always produce a byte-identical spec.

.PARAMETER InputSpec
    Path to the source openapi.json. Defaults to the repo-root spec relative to this
    script (.build/.. ).

.PARAMETER OutputSpec
    Path to write the enriched spec. Defaults to InputSpec (in-place rewrite).

.PARAMETER FrontendRepoPath
    Path to a checkout of the CIPP frontend repository. Provides both the shape
    baselines (Tests/Shapes) and the page column declarations (src).

.PARAMETER PassThru
    Return the enriched spec object instead of only writing it. Used by tests.

.EXAMPLE
    ./Add-OpenApiResponseSchemas.ps1 -FrontendRepoPath ../CIPP

    Rewrites the repo-root openapi.json in place with typed response schemas.
#>
[CmdletBinding()]
param(
    [string]$InputSpec = (Join-Path $PSScriptRoot '..' 'openapi.json'),
    [string]$OutputSpec,
    [string]$FrontendRepoPath,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$script:CippHttpMethods = @('get', 'post', 'put', 'patch', 'delete')

function ConvertFrom-ShapeNode {
    <#
    .SYNOPSIS
        Converts one node of a captured shape tree into an OpenAPI schema fragment.
    #>
    param($Node)

    if ($Node -is [string]) {
        switch ($Node) {
            'string' { return @{ type = 'string' } }
            'number' { return @{ type = 'number' } }
            'bool' { return @{ type = 'boolean' } }
            'datetime' { return [ordered]@{ type = 'string'; format = 'date-time' } }
            # 'null' (captured as null at sample time) and 'truncated' (below the
            # capture depth limit) carry no reliable type, so stay permissive.
            default { return @{} }
        }
    }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node['_type'] -eq 'array') {
            return [ordered]@{ type = 'array'; items = (ConvertFrom-ShapeNode -Node $Node['_element']) }
        }
        $properties = [ordered]@{}
        foreach ($key in ($Node.Keys | Sort-Object)) {
            $properties[[string]$key] = ConvertFrom-ShapeNode -Node $Node[$key]
        }
        return [ordered]@{ type = 'object'; properties = $properties }
    }

    return @{}
}

function Get-ShapeBaselineMap {
    <#
    .SYNOPSIS
        Maps endpoint name -> per-record OpenAPI schema, from captured shape baselines.
    .DESCRIPTION
        Reads only files carrying both _metadata and shape; the sibling
        test-results.json and any non-baseline file is skipped. The per-record schema
        is the baseline shape itself (the CIPP envelope's Results[] element).
    #>
    param([string]$ShapesDir)

    $map = @{}
    if (-not (Test-Path $ShapesDir)) {
        Write-Warning "Shapes directory not found: $ShapesDir"
        return $map
    }

    foreach ($file in (Get-ChildItem -Path $ShapesDir -Filter '*.json' | Sort-Object -Property FullName)) {
        $doc = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        if (-not ($doc -is [System.Collections.IDictionary] -and $doc.ContainsKey('_metadata') -and $doc.ContainsKey('shape'))) {
            continue
        }
        $endpoint = $doc['_metadata']['endpoint']
        if (-not $endpoint) { continue }
        $map[$endpoint] = ConvertFrom-ShapeNode -Node $doc['shape']
    }
    return $map
}

function Get-FrontendColumnMap {
    <#
    .SYNOPSIS
        Maps endpoint name -> sorted unique field names, from page simpleColumns.
    .DESCRIPTION
        Intent: skips conditional simpleColumns arrays to avoid non-column branch strings; false negatives beat junk fields.
        Scans frontend page sources for files that pair an /api/<Endpoint> reference
        with a simpleColumns array, and unions the declared column names per endpoint.
        Field names are deterministic; their types are not, so callers type them as
        string with a provenance marker.
    #>
    param([string]$SrcDir)

    $map = @{}
    if (-not (Test-Path $SrcDir)) {
        Write-Warning "Frontend src directory not found: $SrcDir"
        return $map
    }

    $endpointPattern = [regex]'/api/([A-Za-z0-9_]+)'
    $columnsPattern = [regex]'(?s)\bsimpleColumns\s*(?:=|:)\s*(?:\{\s*)?\[(?<columns>[^\]]*)\]'
    $stringPattern = [regex]'"([^"]+)"|''([^'']+)'''

    $files = Get-ChildItem -Path $SrcDir -Recurse -File -Include '*.js', '*.jsx'
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if ([string]::IsNullOrEmpty($text) -or $text -notmatch 'simpleColumns') { continue }

        $endpoints = $endpointPattern.Matches($text) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        if (-not $endpoints) { continue }

        $columns = foreach ($colMatch in $columnsPattern.Matches($text)) {
            foreach ($strMatch in $stringPattern.Matches($colMatch.Groups['columns'].Value)) {
                $value = if ($strMatch.Groups[1].Success) { $strMatch.Groups[1].Value } else { $strMatch.Groups[2].Value }
                if ($value) { $value }
            }
        }
        if (-not $columns) { continue }

        foreach ($endpoint in $endpoints) {
            if (-not $map.ContainsKey($endpoint)) { $map[$endpoint] = [System.Collections.Generic.HashSet[string]]::new() }
            foreach ($column in $columns) { [void]$map[$endpoint].Add($column) }
        }
    }
    return $map
}

function ConvertTo-ColumnRecordSchema {
    <#
    .SYNOPSIS
        Builds a per-record object schema from a set of frontend column names.
    #>
    param([System.Collections.Generic.HashSet[string]]$Columns)

    $properties = [ordered]@{}
    foreach ($column in ($Columns | Sort-Object)) {
        $properties[$column] = [ordered]@{ type = 'string'; 'x-cipp-field-source' = 'frontend' }
    }
    return [ordered]@{ type = 'object'; properties = $properties }
}

function ConvertTo-ResponseEnvelopeSchema {
    <#
    .SYNOPSIS
        Wraps a per-record schema in the CIPP { Results: [...], Metadata: {...} } envelope.
    #>
    param($RecordSchema)

    return [ordered]@{
        type       = 'object'
        properties = [ordered]@{
            Results  = [ordered]@{ type = 'array'; items = $RecordSchema }
            Metadata = [ordered]@{ type = 'object' }
        }
    }
}


function Get-CippOperationId {
    <#
    .SYNOPSIS
        Builds the deterministic operationId for one CIPP path and method.
    .DESCRIPTION
        Riftwing imports OpenAPI operations by operationId. CIPP upstream does not
        currently emit operationIds, so this keeps importer keys stable without
        depending on display labels or external data.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string[]]$PathMethods
    )

    $endpointName = $Path -replace '^/api/', ''
    if ($PathMethods.Count -eq 1) {
        return $endpointName
    }

    $methodName = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($Method.ToLowerInvariant())
    return "$methodName$endpointName"
}

function Add-CippOperationId {
    <#
    .SYNOPSIS
        Injects missing operationIds and fails on duplicate operationIds.
    .DESCRIPTION
        Existing non-empty operationIds are preserved so this pass can retire itself
        when upstream starts emitting operationIds. Duplicate operationIds are fatal
        because importers commonly key operations by operationId.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Spec)

    if (-not $Spec['paths']) { throw 'Spec has no paths.' }

    $operationCount = 0
    $injectedCount = 0
    $operationIds = @{}

    foreach ($pathEntry in $Spec['paths'].GetEnumerator()) {
        $pathMethods = @($pathEntry.Value.Keys | Where-Object { $_ -in $script:CippHttpMethods })
        foreach ($methodEntry in $pathEntry.Value.GetEnumerator()) {
            if ($methodEntry.Key -notin $script:CippHttpMethods) { continue }

            $operationCount++
            $operation = $methodEntry.Value
            $operationId = $operation['operationId']
            if ([string]::IsNullOrWhiteSpace([string]$operationId)) {
                $operationId = Get-CippOperationId -Path $pathEntry.Key -Method $methodEntry.Key -PathMethods $pathMethods
                $operation['operationId'] = $operationId
                $injectedCount++
            }

            if ($operationIds.ContainsKey($operationId)) {
                throw "Duplicate operationId found: $operationId"
            }
            $operationIds[$operationId] = $true
        }
    }

    return [pscustomobject]@{ Operations = $operationCount; Injected = $injectedCount; Unique = $operationIds.Count }
}

function Resolve-SpecResponse {
    <#
    .SYNOPSIS
        Adds typed 200 response schemas to a parsed spec, in place, and returns counts.
    .DESCRIPTION
        The pure core of this stage: operates on an already-parsed spec hashtable and
        the two endpoint maps, with no file or repository access, so it is unit
        testable. Only existing 200 responses on get/post/put/patch/delete operations
        are touched; everything else (including operations with no matching source) is
        left exactly as found.
    #>
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Spec,
        [Parameter(Mandatory)][hashtable]$BaselineMap,
        [Parameter(Mandatory)][hashtable]$ColumnMap
    )

    if (-not $Spec['paths']) { throw 'Spec has no paths.' }

    $operationCount = 0
    $typedCount = 0

    foreach ($pathEntry in $Spec['paths'].GetEnumerator()) {
        $endpoint = $pathEntry.Key -replace '^/api/', ''

        $recordSchema = $null
        if ($BaselineMap.ContainsKey($endpoint)) {
            $recordSchema = $BaselineMap[$endpoint]
        } elseif ($ColumnMap.ContainsKey($endpoint)) {
            $recordSchema = ConvertTo-ColumnRecordSchema -Columns $ColumnMap[$endpoint]
        }

        foreach ($methodEntry in $pathEntry.Value.GetEnumerator()) {
            if ($methodEntry.Key -notin $script:CippHttpMethods) { continue }
            $operationCount++
            if ($null -eq $recordSchema) { continue }

            $responses = $methodEntry.Value['responses']
            if ($null -eq $responses) { continue }

            $okResponse = $responses['200']
            if (-not $okResponse) { continue }

            $okResponse['content'] = [ordered]@{
                'application/json' = [ordered]@{ schema = (ConvertTo-ResponseEnvelopeSchema -RecordSchema $recordSchema) }
            }
            $typedCount++
        }
    }

    return [pscustomobject]@{
        Operations         = $operationCount
        Typed              = $typedCount
    }
}

function Add-CippResponseSchema {
    <#
    .SYNOPSIS
        File-level orchestration: read spec + repo sources, enrich, write output.
    #>
    param(
        [Parameter(Mandatory)][string]$InputSpec,
        [Parameter(Mandatory)][string]$OutputSpec,
        [Parameter(Mandatory)][string]$FrontendRepoPath,
        [switch]$PassThru
    )

    if (-not (Test-Path $InputSpec)) { throw "Input spec not found: $InputSpec" }

    $spec = Get-Content -LiteralPath $InputSpec -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $baselineMap = Get-ShapeBaselineMap -ShapesDir (Join-Path $FrontendRepoPath 'Tests' 'Shapes')
    $columnMap = Get-FrontendColumnMap -SrcDir (Join-Path $FrontendRepoPath 'src')

    $operationIdResult = Add-CippOperationId -Spec $spec
    $result = Resolve-SpecResponse -Spec $spec -BaselineMap $baselineMap -ColumnMap $columnMap
    Write-Information "Operations: $($result.Operations) | typed responses added: $($result.Typed) | operationIds injected: $($operationIdResult.Injected) | unique operationIds: $($operationIdResult.Unique)" -InformationAction Continue

    # Serialization is deterministic for the object this stage builds, but it does not globally canonicalize pre-existing spec keys.
    [System.IO.File]::WriteAllText($OutputSpec, ($spec | ConvertTo-Json -Depth 100))

    if ($PassThru) { return $spec }
}

# Run orchestration only when invoked as a script, not when dot-sourced for testing.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $FrontendRepoPath) { throw 'FrontendRepoPath is required when running the script.' }
    if (-not $OutputSpec) { $OutputSpec = $InputSpec }
    Add-CippResponseSchema -InputSpec $InputSpec -OutputSpec $OutputSpec -FrontendRepoPath $FrontendRepoPath -PassThru:$PassThru
}
