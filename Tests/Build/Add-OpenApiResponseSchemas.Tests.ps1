#Requires -Version 7.0
<#
    Pester tests for Add-OpenApiResponseSchemas.ps1.

    Covers the pure core (Resolve-SpecResponse + the schema/source converters) with
    hand-built fixtures, plus the sad paths that matter for a generator stage:
    malformed input, non-baseline files, missing sources, and operations the stage
    must leave untouched. Dot-sources the script so only its functions load.
#>

BeforeAll {
    # Test lives at <repo>/Tests/Build/; the script lives at <repo>/.build/.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ScriptPath = Join-Path $RepoRoot '.build' 'Add-OpenApiResponseSchemas.ps1'
    . $ScriptPath

    # Minimal spec factory: one path with the given methods, each carrying a bare 200.
    function Get-TestSpec {
        param([hashtable]$Paths)
        return [ordered]@{ openapi = '3.1.0'; paths = $Paths }
    }
    function Get-Operation {
        param(
            [switch]$NoOkResponse,
            [string]$OperationId
        )
        $responses = if ($NoOkResponse) { @{ '500' = @{ description = 'err' } } } else { @{ '200' = @{ description = 'ok' } } }
        $operation = @{ responses = $responses }
        if ($OperationId) { $operation['operationId'] = $OperationId }
        return $operation
    }
}

Describe 'ConvertFrom-ShapeNode' {
    Context 'Leaf tokens' {
        It 'maps string' { (ConvertFrom-ShapeNode -Node 'string').type | Should -Be 'string' }
        It 'maps number' { (ConvertFrom-ShapeNode -Node 'number').type | Should -Be 'number' }
        It 'maps bool to boolean' { (ConvertFrom-ShapeNode -Node 'bool').type | Should -Be 'boolean' }
        It 'maps datetime to string+format' {
            $r = ConvertFrom-ShapeNode -Node 'datetime'
            $r.type | Should -Be 'string'
            $r.format | Should -Be 'date-time'
        }
        It 'leaves null permissive (no type)' { (ConvertFrom-ShapeNode -Node 'null').Keys.Count | Should -Be 0 }
        It 'leaves truncated permissive (no type)' { (ConvertFrom-ShapeNode -Node 'truncated').Keys.Count | Should -Be 0 }
        It 'leaves unknown tokens permissive' { (ConvertFrom-ShapeNode -Node 'mystery').Keys.Count | Should -Be 0 }
    }

    Context 'Nested structures' {
        It 'maps an array node to type array with typed items' {
            $node = @{ _type = 'array'; _element = 'string' }
            $r = ConvertFrom-ShapeNode -Node $node
            $r.type | Should -Be 'array'
            $r.items.type | Should -Be 'string'
        }
        It 'maps an object node and sorts its properties' {
            $node = [ordered]@{ zeta = 'string'; alpha = 'number' }
            $r = ConvertFrom-ShapeNode -Node $node
            $r.type | Should -Be 'object'
            @($r.properties.Keys) | Should -Be @('alpha', 'zeta')
        }
        It 'maps an array of objects' {
            $node = @{ _type = 'array'; _element = @{ id = 'string'; count = 'number' } }
            $r = ConvertFrom-ShapeNode -Node $node
            $r.items.type | Should -Be 'object'
            $r.items.properties.id.type | Should -Be 'string'
        }
    }
}

Describe 'ConvertTo-ColumnRecordSchema' {
    It 'types every column as string with frontend provenance' {
        $cols = [System.Collections.Generic.HashSet[string]]::new()
        [void]$cols.Add('mail'); [void]$cols.Add('displayName')
        $r = ConvertTo-ColumnRecordSchema -Columns $cols
        $r.type | Should -Be 'object'
        $r.properties.mail.type | Should -Be 'string'
        $r.properties.mail.'x-cipp-field-source' | Should -Be 'frontend'
    }
    It 'sorts columns for deterministic output' {
        $cols = [System.Collections.Generic.HashSet[string]]::new()
        [void]$cols.Add('zeta'); [void]$cols.Add('alpha')
        $r = ConvertTo-ColumnRecordSchema -Columns $cols
        @($r.properties.Keys) | Should -Be @('alpha', 'zeta')
    }
}

Describe 'ConvertTo-ResponseEnvelopeSchema' {
    It 'wraps a record schema in the Results/Metadata envelope' {
        $record = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } }
        $r = ConvertTo-ResponseEnvelopeSchema -RecordSchema $record
        $r.type | Should -Be 'object'
        $r.properties.Results.type | Should -Be 'array'
        $r.properties.Results.items.properties.id.type | Should -Be 'string'
        $r.properties.Metadata.type | Should -Be 'object'
    }
}


Describe 'Add-CippOperationId' {
    It 'injects the bare endpoint name for a single-method operation with no operationId' {
        $spec = Get-TestSpec -Paths @{ '/api/ListMailboxes' = @{ get = (Get-Operation) } }
        $r = Add-CippOperationId -Spec $spec
        $spec['paths']['/api/ListMailboxes']['get']['operationId'] | Should -Be 'ListMailboxes'
        $r.Injected | Should -Be 1
        $r.Unique | Should -Be 1
    }

    It 'keeps single-method endpoint names bare even when they start with their method word' {
        $spec = Get-TestSpec -Paths @{
            '/api/PatchUser' = @{ patch = (Get-Operation) }
            '/api/ListX'     = @{ get = (Get-Operation) }
        }
        Add-CippOperationId -Spec $spec | Out-Null
        $spec['paths']['/api/PatchUser']['patch']['operationId'] | Should -Be 'PatchUser'
        $spec['paths']['/api/ListX']['get']['operationId'] | Should -Be 'ListX'
    }

    It 'gives a multi-method path two distinct operationIds' {
        $spec = Get-TestSpec -Paths @{ '/api/ExecCSPLicense' = @{ get = (Get-Operation); post = (Get-Operation) } }
        $r = Add-CippOperationId -Spec $spec
        $spec['paths']['/api/ExecCSPLicense']['get']['operationId'] | Should -Be 'GetExecCSPLicense'
        $spec['paths']['/api/ExecCSPLicense']['post']['operationId'] | Should -Be 'PostExecCSPLicense'
        $r.Unique | Should -Be 2
    }

    It 'preserves a pre-existing operationId' {
        $spec = Get-TestSpec -Paths @{ '/api/ListMailboxes' = @{ get = (Get-Operation -OperationId 'AlreadyThere') } }
        $r = Add-CippOperationId -Spec $spec
        $spec['paths']['/api/ListMailboxes']['get']['operationId'] | Should -Be 'AlreadyThere'
        $r.Injected | Should -Be 0
    }

    It 'throws when a synthetic duplicate operationId is present' {
        $spec = Get-TestSpec -Paths @{
            '/api/DuplicateA' = @{ get = (Get-Operation -OperationId 'SameOperation') }
            '/api/DuplicateB' = @{ post = (Get-Operation -OperationId 'SameOperation') }
        }
        { Add-CippOperationId -Spec $spec } | Should -Throw '*Duplicate operationId found: SameOperation*'
    }

    It 'keeps visibly different endpoint names distinct without hidden normalization' {
        $spec = Get-TestSpec -Paths @{
            '/api/User'       = @{ get = (Get-Operation) }
            '/api/ListUsers'  = @{ get = (Get-Operation) }
            '/api/List-Users' = @{ get = (Get-Operation) }
        }
        Add-CippOperationId -Spec $spec | Out-Null
        $spec['paths']['/api/User']['get']['operationId'] | Should -Be 'User'
        $spec['paths']['/api/ListUsers']['get']['operationId'] | Should -Be 'ListUsers'
        $spec['paths']['/api/List-Users']['get']['operationId'] | Should -Be 'List-Users'
    }

    It 'throws when disambiguated derivation creates an actual duplicate' {
        $spec = Get-TestSpec -Paths @{
            '/api/PatchUser' = @{ patch = (Get-Operation) }
            '/api/User'      = @{ get = (Get-Operation); patch = (Get-Operation) }
        }
        { Add-CippOperationId -Spec $spec } | Should -Throw '*Duplicate operationId found: PatchUser*'
    }

    It 'throws when two single-method paths have the same bare endpoint name' {
        $spec = Get-TestSpec -Paths @{
            '/api/SameName' = @{ get = (Get-Operation) }
            'SameName'      = @{ post = (Get-Operation) }
        }
        { Add-CippOperationId -Spec $spec } | Should -Throw '*Duplicate operationId found: SameName*'
    }

    It 'ignores non-method path item keys when injecting operationIds' {
        $spec = Get-TestSpec -Paths @{
            '/api/ListThings' = [ordered]@{
                get         = (Get-Operation)
                parameters  = @(@{ name = 'tenant'; in = 'query' })
                summary     = 'path summary'
                '$ref'      = '#/components/pathItems/ListThings'
                description = 'path description'
            }
        }
        Add-CippOperationId -Spec $spec | Out-Null
        $spec['paths']['/api/ListThings']['get']['operationId'] | Should -Be 'ListThings'
        $spec['paths']['/api/ListThings']['parameters'][0].ContainsKey('operationId') | Should -BeFalse
        $spec['paths']['/api/ListThings']['summary'] | Should -Be 'path summary'
        $spec['paths']['/api/ListThings']['$ref'] | Should -Be '#/components/pathItems/ListThings'
        $spec['paths']['/api/ListThings']['description'] | Should -Be 'path description'
    }

    It 'yields one unique operationId per operation on the full real spec' {
        $specPath = Join-Path $RepoRoot 'openapi.json'
        $spec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $operationTotal = 0
        foreach ($pathEntry in $spec['paths'].GetEnumerator()) {
            foreach ($methodEntry in $pathEntry.Value.GetEnumerator()) {
                if ($methodEntry.Key -in @('get', 'post', 'put', 'patch', 'delete')) { $operationTotal++ }
            }
        }
        $r = Add-CippOperationId -Spec $spec
        Write-Information "Full real spec operationIds: $($r.Unique)" -InformationAction Continue
        $r.Operations | Should -Be $operationTotal
        $r.Unique | Should -Be $r.Operations
    }
}

Describe 'Resolve-SpecResponse - happy paths' {
    It 'types a baseline-backed endpoint and counts it' {
        $spec = Get-TestSpec -Paths @{ '/api/ListThings' = @{ get = (Get-Operation) } }
        $baseline = @{ ListThings = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } } }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $r.Operations | Should -Be 1
        $r.Typed | Should -Be 1
        $schema = $spec['paths']['/api/ListThings']['get']['responses']['200']['content']['application/json']['schema']
        $schema.properties.Results.items.properties.id.type | Should -Be 'string'
    }

    It 'prefers the baseline when an endpoint is in both maps' {
        $spec = Get-TestSpec -Paths @{ '/api/Both' = @{ get = (Get-Operation) } }
        $baseline = @{ Both = [ordered]@{ type = 'object'; properties = [ordered]@{ fromBaseline = @{ type = 'string' } } } }
        $cols = [System.Collections.Generic.HashSet[string]]::new(); [void]$cols.Add('fromColumns')
        Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{ Both = $cols } | Out-Null
        $props = $spec['paths']['/api/Both']['get']['responses']['200']['content']['application/json']['schema'].properties.Results.items.properties
        $props.Keys | Should -Contain 'fromBaseline'
        $props.Keys | Should -Not -Contain 'fromColumns'
    }



    It 'does not inject operationIds while typing responses' {
        $spec = Get-TestSpec -Paths @{ '/api/ListThings' = @{ get = (Get-Operation) } }
        $baseline = @{ ListThings = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } } }
        Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{} | Out-Null
        $spec['paths']['/api/ListThings']['get'].ContainsKey('operationId') | Should -BeFalse
    }

    It 'types a columns-only endpoint with provenance markers' {
        $spec = Get-TestSpec -Paths @{ '/api/ListCols' = @{ get = (Get-Operation) } }
        $cols = [System.Collections.Generic.HashSet[string]]::new(); [void]$cols.Add('displayName')
        Resolve-SpecResponse -Spec $spec -BaselineMap @{} -ColumnMap @{ ListCols = $cols } | Out-Null
        $props = $spec['paths']['/api/ListCols']['get']['responses']['200']['content']['application/json']['schema'].properties.Results.items.properties
        $props.displayName.'x-cipp-field-source' | Should -Be 'frontend'
    }
}

Describe 'Resolve-SpecResponse - sad paths and invariants' {
    It 'leaves an endpoint with no matching source untouched' {
        $spec = Get-TestSpec -Paths @{ '/api/AddUser' = @{ post = (Get-Operation) } }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap @{} -ColumnMap @{}
        $r.Operations | Should -Be 1
        $r.Typed | Should -Be 0
        $spec['paths']['/api/AddUser']['post']['responses']['200'].ContainsKey('content') | Should -BeFalse
    }

    It 'does not type an operation that has no 200 response' {
        $spec = Get-TestSpec -Paths @{ '/api/Weird' = @{ get = (Get-Operation -NoOkResponse) } }
        $baseline = @{ Weird = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } } }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $r.Typed | Should -Be 0
    }

    It 'does not throw on an operation with no responses block' {
        $spec = Get-TestSpec -Paths @{ '/api/Weird' = @{ get = @{} } }
        $baseline = @{ Weird = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } } }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $r.Operations | Should -Be 1
        $r.Typed | Should -Be 0
    }

    It 'types a baseline-backed endpoint even when the record schema is permissive' {
        $spec = Get-TestSpec -Paths @{ '/api/ListUnknown' = @{ get = (Get-Operation) } }
        $baseline = @{ ListUnknown = @{} }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $r.Typed | Should -Be 1
        $schema = $spec['paths']['/api/ListUnknown']['get']['responses']['200']['content']['application/json']['schema']
        $schema.properties.Results.items.Keys.Count | Should -Be 0
    }

    It 'counts only get/post/put/patch/delete, ignoring parameters/summary keys' {
        $spec = Get-TestSpec -Paths @{ '/api/ListThings' = [ordered]@{ get = (Get-Operation); parameters = @(); summary = 'x' } }
        $r = Resolve-SpecResponse -Spec $spec -BaselineMap @{} -ColumnMap @{}
        $r.Operations | Should -Be 1
    }

    It 'preserves the operation set (adds nothing, removes nothing)' {
        $spec = Get-TestSpec -Paths @{
            '/api/ListA' = @{ get = (Get-Operation) }
            '/api/AddB'  = @{ post = (Get-Operation) }
        }
        $before = $spec['paths'].Keys | Sort-Object
        Resolve-SpecResponse -Spec $spec -BaselineMap @{} -ColumnMap @{} | Out-Null
        ($spec['paths'].Keys | Sort-Object) | Should -Be $before
    }

    It 'throws on a spec with no paths' {
        { Resolve-SpecResponse -Spec ([ordered]@{ openapi = '3.1.0' }) -BaselineMap @{} -ColumnMap @{} } |
            Should -Throw '*no paths*'
    }

    It 'is stable on a second core pass (same count, same typed schema)' {
        # Production never re-mutates an in-memory spec; it reads fresh each run. The
        # guarantee that matters is that re-applying yields the same meaningful output,
        # not that an unordered Hashtable serialises in identical key order.
        $spec = Get-TestSpec -Paths @{ '/api/ListThings' = @{ get = (Get-Operation) } }
        $baseline = @{ ListThings = [ordered]@{ type = 'object'; properties = [ordered]@{ id = @{ type = 'string' } } } }
        $r1 = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $schema1 = $spec['paths']['/api/ListThings']['get']['responses']['200']['content']['application/json']['schema'] | ConvertTo-Json -Depth 100
        $r2 = Resolve-SpecResponse -Spec $spec -BaselineMap $baseline -ColumnMap @{}
        $schema2 = $spec['paths']['/api/ListThings']['get']['responses']['200']['content']['application/json']['schema'] | ConvertTo-Json -Depth 100
        $r2.Typed | Should -Be $r1.Typed
        $schema2 | Should -Be $schema1
    }
}

Describe 'Get-ShapeBaselineMap - file ingestion sad paths' {
    BeforeEach {
        $script:ShapesDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-shapes-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:ShapesDir -Force | Out-Null
    }
    AfterEach { Remove-Item -Recurse -Force $script:ShapesDir -ErrorAction SilentlyContinue }

    It 'ingests a valid baseline' {
        @{ _metadata = @{ endpoint = 'ListX' }; shape = @{ id = 'string' } } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $script:ShapesDir 'ListX.json')
        $map = Get-ShapeBaselineMap -ShapesDir $script:ShapesDir
        $map.ContainsKey('ListX') | Should -BeTrue
    }

    It 'skips a file that lacks _metadata/shape (e.g. test-results.json)' {
        @{ results = @(@{ status = 'PASS' }) } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $script:ShapesDir 'test-results.json')
        $map = Get-ShapeBaselineMap -ShapesDir $script:ShapesDir
        $map.Count | Should -Be 0
    }

    It 'returns empty for a missing directory without throwing' {
        $map = Get-ShapeBaselineMap -ShapesDir (Join-Path $script:ShapesDir 'does-not-exist')
        $map.Count | Should -Be 0
    }
}

Describe 'Get-FrontendColumnMap - parsing sad paths' {
    BeforeEach {
        $script:SrcDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-src-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:SrcDir -Force | Out-Null
    }
    AfterEach { Remove-Item -Recurse -Force $script:SrcDir -ErrorAction SilentlyContinue }

    It 'extracts columns paired with an api endpoint' {
        Set-Content (Join-Path $script:SrcDir 'page.jsx') @'
const simpleColumns = ["displayName", "mail"];
<Component apiUrl="/api/ListMailboxes" simpleColumns={simpleColumns} />
'@
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map['ListMailboxes'] | Should -Contain 'displayName'
        $map['ListMailboxes'] | Should -Contain 'mail'
    }

    It 'handles mixed single and double quotes in the column array' {
        Set-Content (Join-Path $script:SrcDir 'page.jsx') @'
const simpleColumns = ['mail', "displayName"];
apiUrl="/api/ListThings"
'@
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map['ListThings'].Count | Should -Be 2
    }

    It 'handles JSX simpleColumns arrays split after the opening brace' {
        Set-Content (Join-Path $script:SrcDir 'page.jsx') @'
<CippDataTable
  apiUrl="/api/ListSplit"
  simpleColumns={
    ["displayName", "mail"]
  }
/>
'@
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map['ListSplit'] | Should -Contain 'displayName'
        $map['ListSplit'] | Should -Contain 'mail'
    }



    It 'does not leak scalar ternary branch strings near simpleColumns' {
        Set-Content (Join-Path $script:SrcDir 'page.jsx') @'
const statusLabel = enabled ? "yes" : "no";
const simpleColumns = ["displayName", "mail"];
apiUrl="/api/ListTernarySafe"
'@
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map['ListTernarySafe'] | Should -Contain 'displayName'
        $map['ListTernarySafe'] | Should -Contain 'mail'
        $map['ListTernarySafe'] | Should -Not -Contain 'yes'
        $map['ListTernarySafe'] | Should -Not -Contain 'no'
    }

    It 'does not capture branch strings when simpleColumns is a ternary of arrays' {
        # This lightweight parser only accepts direct array literals. Conditional
        # simpleColumns values are ignored rather than risking scalar branch leaks.
        Set-Content (Join-Path $script:SrcDir 'page.jsx') @'
const simpleColumns = hasScope
  ? ['RowKey', 'Value', 'Description']
  : ['RowKey', 'Value', 'Description', 'Scope'];
const label = hasScope ? "yes" : "no";
apiUrl="/api/ListCustomVariables"
'@
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map.ContainsKey('ListCustomVariables') | Should -BeFalse
        foreach ($columns in $map.Values) {
            $columns | Should -Not -Contain 'yes'
            $columns | Should -Not -Contain 'no'
        }
    }

    It 'ignores a file with simpleColumns but no api endpoint' {
        Set-Content (Join-Path $script:SrcDir 'page.jsx') 'const simpleColumns = ["x"];'
        $map = Get-FrontendColumnMap -SrcDir $script:SrcDir
        $map.Count | Should -Be 0
    }

    It 'does not crash on an empty file' {
        Set-Content (Join-Path $script:SrcDir 'empty.jsx') ''
        { Get-FrontendColumnMap -SrcDir $script:SrcDir } | Should -Not -Throw
    }

    It 'returns empty for a missing src directory without throwing' {
        $map = Get-FrontendColumnMap -SrcDir (Join-Path $script:SrcDir 'nope')
        $map.Count | Should -Be 0
    }
}

Describe 'Add-CippResponseSchema - end to end on a temp spec' {
    It 'throws when the input spec does not exist' {
        { Add-CippResponseSchema -InputSpec 'X:\nope.json' -OutputSpec 'X:\out.json' -FrontendRepoPath '.' } |
            Should -Throw '*not found*'
    }

    It 'throws when the input spec contains malformed JSON' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-bad-json-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $tmp 'Tests' 'Shapes') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'src') -Force | Out-Null
        $specPath = Join-Path $tmp 'openapi.json'
        $outPath = Join-Path $tmp 'out.json'
        Set-Content -LiteralPath $specPath -Value '{ "openapi": "3.1.0", "paths": '

        { Add-CippResponseSchema -InputSpec $specPath -OutputSpec $outPath -FrontendRepoPath $tmp } |
            Should -Throw

        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    It 'reads, enriches, and writes a real file round-trip' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-e2e-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $tmp | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'Tests' 'Shapes') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'src') -Force | Out-Null
        @{ _metadata = @{ endpoint = 'ListThings' }; shape = @{ id = 'string' } } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $tmp 'Tests' 'Shapes' 'ListThings.json')
        $specPath = Join-Path $tmp 'openapi.json'
        $outPath = Join-Path $tmp 'out.json'
        Get-TestSpec -Paths @{ '/api/ListThings' = @{ get = (Get-Operation) } } | ConvertTo-Json -Depth 100 |
            Set-Content $specPath

        Add-CippResponseSchema -InputSpec $specPath -OutputSpec $outPath -FrontendRepoPath $tmp | Out-Null
        $out = Get-Content $outPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $out['paths']['/api/ListThings']['get']['responses']['200']['content']['application/json']['schema'].properties.Results.items.properties.id.type |
            Should -Be 'string'
        $out['paths']['/api/ListThings']['get']['operationId'] | Should -Be 'ListThings'

        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    It 'is byte-identical when run twice on the same sources (file-level idempotency)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-idem-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $tmp 'Tests' 'Shapes') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp 'src') -Force | Out-Null
        @{ _metadata = @{ endpoint = 'ListThings' }; shape = @{ id = 'string'; when = 'datetime' } } | ConvertTo-Json -Depth 10 |
            Set-Content (Join-Path $tmp 'Tests' 'Shapes' 'ListThings.json')
        $specPath = Join-Path $tmp 'openapi.json'
        Get-TestSpec -Paths @{ '/api/ListThings' = @{ get = (Get-Operation) } } | ConvertTo-Json -Depth 100 |
            Set-Content $specPath

        $out1 = Join-Path $tmp 'o1.json'
        $out2 = Join-Path $tmp 'o2.json'
        Add-CippResponseSchema -InputSpec $specPath -OutputSpec $out1 -FrontendRepoPath $tmp | Out-Null
        Add-CippResponseSchema -InputSpec $out1 -OutputSpec $out2 -FrontendRepoPath $tmp | Out-Null
        (Get-Content $out2 -Raw) | Should -Be (Get-Content $out1 -Raw)

        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}
