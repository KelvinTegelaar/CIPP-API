# Contract tests for the shipped backend/Config/openapi.json.
#
# Build-OpenApi.Tests.ps1 tests the generator against fixtures. This file tests the
# artifact that actually ships, against the real entrypoint sources, using its own
# independent reading of those sources rather than the generator's. If both were
# derived the same way a bug in the extraction would agree with itself.
#
# The spec is not documentation. Get-CippMcpSpec loads it at runtime and
# Get-CippMcpToolList projects it into the MCP tool list, so these invariants are
# what stand between a source change and a wrong tool contract in production.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:SpecPath = Join-Path $BackendRoot 'Config/openapi.json'
    if (-not (Test-Path $script:SpecPath)) { throw "openapi.json not found at $script:SpecPath" }

    # -AsHashtable: the spec carries keys differing only in case (displayName /
    # DisplayName), which a case-insensitive PSCustomObject silently collapses.
    $script:Spec = [System.IO.File]::ReadAllText($script:SpecPath) | ConvertFrom-Json -AsHashtable -Depth 100

    $script:EntrypointRoot = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    $FunctionName = [regex]::new('(?im)^\s*function\s+(Invoke-[\w-]+)')
    $Entrypoint = [regex]::new('(?is)\.FUNCTIONALITY\s+.*?\bEntrypoint\b')
    # deliberately a plain scan, independent of the generator's AST walk
    $ValueRead = [regex]::new('\$Request\.Body\.([A-Za-z0-9_]+)\.(value|label)\b')
    $BodyRead = [regex]::new('\$Request\.Body\.([A-Za-z0-9_]+)')

    $script:Sources = @(
        foreach ($File in Get-ChildItem -Path $script:EntrypointRoot -Filter 'Invoke-*.ps1' -Recurse -File) {
            $Text = [System.IO.File]::ReadAllText($File.FullName)
            $Match = $FunctionName.Match($Text)
            if (-not $Match.Success) { continue }
            if (-not $Entrypoint.IsMatch($Text)) { continue }
            [pscustomobject]@{
                # the function name is what New-CippCoreRequest resolves, and four
                # files disagree with it in case
                Endpoint    = $Match.Groups[1].Value -replace '^Invoke-', ''
                File        = $File.Name
                ValueFields = @($ValueRead.Matches($Text) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                BodyFields  = @($BodyRead.Matches($Text) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            }
        }
    )

    function Get-SoleOperation {
        param([string]$Endpoint)
        $PathItem = $script:Spec.paths["/api/$Endpoint"]
        if (-not $PathItem) { return $null }
        $Method = @($PathItem.Keys)[0]
        return [pscustomobject]@{ Method = $Method; Operation = $PathItem[$Method] }
    }

    function Get-BodySchema {
        param($Operation)
        $Schema = $Operation.requestBody.content.'application/json'.schema
        if ($Schema.type -eq 'array') { return $Schema.items }
        return $Schema
    }
}

Describe 'coverage against the entrypoint sources' {
    It 'found entrypoints to check' {
        $script:Sources.Count | Should -BeGreaterThan 500
    }

    It 'documents every function marked Entrypoint' {
        $Missing = @($script:Sources | Where-Object { -not $script:Spec.paths.ContainsKey("/api/$($_.Endpoint)") })
        $Missing.Endpoint | Should -BeNullOrEmpty -Because 'an undocumented endpoint is also an endpoint MCP cannot see'
    }

    It 'documents no path without a backing function' {
        $Known = @{}
        foreach ($Source in $script:Sources) { $Known[$Source.Endpoint] = $true }
        $Orphans = @($script:Spec.paths.Keys | Where-Object { -not $Known.ContainsKey(($_ -replace '^/api/', '')) })
        # routing is 'Invoke-{0}' -f CIPPEndpoint, so a path with no function is a 404
        $Orphans | Should -BeNullOrEmpty
    }

    It 'names paths after the function, not the file' {
        # invoke-DomainAnalyser_List.ps1 defines Invoke-DomainAnalyser_List; a path of
        # /api/invoke-DomainAnalyser_List would resolve to Invoke-invoke-... and 404
        $script:Spec.paths.Keys | Where-Object { $_ -match '^/api/invoke-' } | Should -BeNullOrEmpty
    }
}

Describe 'request schema fidelity' {
    # This is the regression the generator was rewritten for. The backend reads
    # `$Request.Body.onedriveAccessUser.value`, so a caller must send an object.
    # Documenting it as a plain string made callers send a string, which resolved to
    # $null and made the endpoint silently do nothing.
    It 'never types a field as a bare string when the source reads .value off it' {
        $Wrong = [System.Collections.Generic.List[string]]::new()

        foreach ($Source in $script:Sources) {
            if ($Source.ValueFields.Count -eq 0) { continue }
            $Entry = Get-SoleOperation -Endpoint $Source.Endpoint
            if (-not $Entry) { continue }
            $Schema = Get-BodySchema -Operation $Entry.Operation
            if (-not $Schema -or -not $Schema.properties) { continue }

            foreach ($Field in $Source.ValueFields) {
                $Property = $Schema.properties[$Field]
                if (-not $Property) {
                    $Property = $Schema.properties.GetEnumerator() |
                        Where-Object { $_.Key -eq $Field } | Select-Object -First 1 -ExpandProperty Value
                }
                if (-not $Property) { continue }

                $Rendered = $Property | ConvertTo-Json -Depth 10 -Compress
                $IsObject = $Rendered -match 'LabelValue' -or $Rendered -match '"type":"object"' -or
                    ($Property.type -eq 'array' -and ($Property.items | ConvertTo-Json -Depth 10 -Compress) -match 'LabelValue|"type":"object"')
                if (-not $IsObject) {
                    $Wrong.Add("$($Source.Endpoint).$Field is $Rendered but the source reads .value off it")
                }
            }
        }

        $Wrong | Should -BeNullOrEmpty
    }

    It 'documents LabelValue so callers know value is the field that is read' {
        $script:Spec.components.schemas.LabelValue.properties.Keys | Should -Contain 'value'
        $script:Spec.components.schemas.LabelValue.required | Should -Contain 'value'
    }

    It 'requires tenantFilter wherever the endpoint is tenant-scoped' {
        $Offenders = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $script:Spec.paths.GetEnumerator()) {
            $Method = @($Entry.Value.Keys)[0]
            $Operation = $Entry.Value[$Method]
            if ($Operation.'x-cipp-any-tenant') { continue }

            $Schema = Get-BodySchema -Operation $Operation
            if ($Schema -and $Schema.properties -and $Schema.properties.Contains('tenantFilter')) {
                if (@($Schema.required) -notcontains 'tenantFilter') {
                    $Offenders.Add("$($Entry.Key) body tenantFilter not required")
                }
            }
        }
        $Offenders | Should -BeNullOrEmpty
    }
}

Describe 'invariants the MCP projection depends on' {
    It 'gives every path exactly one operation' {
        # Get-CippMcpToolList names a tool after the endpoint; two operations on one
        # path would advertise two tools with the same name
        $Multi = @($script:Spec.paths.GetEnumerator() | Where-Object { $_.Value.Keys.Count -ne 1 } | ForEach-Object { $_.Key })
        $Multi | Should -BeNullOrEmpty
    }

    It 'uses only methods the API accepts' {
        # the frontend issues axios.get and axios.post only; a patch/delete operation
        # is unreachable and invisible to the MCP projector
        $Bad = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $script:Spec.paths.GetEnumerator()) {
            foreach ($Method in $Entry.Value.Keys) {
                if ($Method -notin @('get', 'post')) { $Bad.Add("$($Entry.Key): $Method") }
            }
        }
        $Bad | Should -BeNullOrEmpty
    }

    It 'classifies an endpoint that reads the request body as POST' {
        # Get-CippMcpToolResult picks Query vs Body purely from the spec's method, so a
        # body-reading endpoint documented as GET receives none of its arguments
        $Bad = @(
            foreach ($Source in $script:Sources) {
                if ($Source.BodyFields.Count -eq 0) { continue }
                $Entry = Get-SoleOperation -Endpoint $Source.Endpoint
                if ($Entry -and $Entry.Method -ne 'post') { "$($Source.Endpoint) is $($Entry.Method) but reads the body" }
            }
        )
        $Bad | Should -BeNullOrEmpty
    }

    It 'gives every operation an x-cipp-role' {
        $Bad = @(
            foreach ($Entry in $script:Spec.paths.GetEnumerator()) {
                foreach ($Method in $Entry.Value.Keys) {
                    if (-not $Entry.Value[$Method].'x-cipp-role') { $Entry.Key }
                }
            }
        )
        $Bad | Should -BeNullOrEmpty
    }

    It 'leaks no raw PowerShell help into descriptions' {
        $Bad = @(
            foreach ($Entry in $script:Spec.paths.GetEnumerator()) {
                foreach ($Method in $Entry.Value.Keys) {
                    $Description = [string]$Entry.Value[$Method].description
                    if ($Description -match '#>|\[CmdletBinding') { $Entry.Key }
                }
            }
        )
        $Bad | Should -BeNullOrEmpty
    }

    It 'resolves every internal $ref it references' {
        $Text = [System.IO.File]::ReadAllText($script:SpecPath)
        $Dangling = [System.Collections.Generic.List[string]]::new()
        foreach ($Match in [regex]::Matches($Text, '"\$ref"\s*:\s*"(#[^"]+)"')) {
            $Node = $script:Spec
            foreach ($Segment in ($Match.Groups[1].Value.TrimStart('#') -split '/' | Where-Object { $_ })) {
                if ($Node -is [System.Collections.IDictionary] -and $Node.Contains($Segment)) { $Node = $Node[$Segment] }
                else { $Node = $null; break }
            }
            if ($null -eq $Node -and -not $Dangling.Contains($Match.Groups[1].Value)) {
                $Dangling.Add($Match.Groups[1].Value)
            }
        }
        $Dangling | Should -BeNullOrEmpty
    }
}

Describe 'the real spec through the real projection' {
    BeforeAll {
        $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
        $McpRoot = Join-Path $BackendRoot 'Modules/CIPPCore/Public/MCP'
        foreach ($Leaf in 'Resolve-CippMcpRef.ps1', 'Resolve-CippMcpNode.ps1', 'Get-CippMcpDescription.ps1',
            'Get-CippMcpSafePropertyName.ps1', 'Get-CippMcpToolCatalog.ps1', 'Get-CippMcpToolList.ps1') {
            . (Join-Path $McpRoot $Leaf)
        }
        function Get-CippMcpSpec { return $script:Spec }
        # The catalog is the whole projected surface. tools/list advertises only the
        # five-tool gateway in front of it, which is asserted separately below.
        $script:Tools = @(Get-CippMcpToolCatalog -Force -InformationAction SilentlyContinue)
    }

    It 'projects a non-trivial tool set' {
        $script:Tools.Count | Should -BeGreaterThan 100
    }

    It 'produces no duplicate tool names' {
        # Get-CippMcpToolResult resolves a call by name and takes the first match
        ($script:Tools.name | Select-Object -Unique).Count | Should -Be $script:Tools.Count
    }

    It 'exposes only read roles' {
        foreach ($Tool in $script:Tools) {
            $Operation = $script:Spec.paths["/api/$($Tool.name)"].Values | Select-Object -First 1
            $Operation.'x-cipp-role' | Should -Match '\.Read$'
        }
    }

    It 'exposes nothing whose name implies a mutation' {
        $script:Tools.name |
            Where-Object { $_ -match '^(Add|Set|Remove|Delete|Edit|New|Update|Disable|Enable|Reset|Revoke|Push|Clear|Start|Stop|Rename|Move|Copy)' } |
            Should -BeNullOrEmpty
    }

    It 'never exposes the MCP transport itself' {
        $script:Tools.name | Should -Not -Contain 'ExecMcp'
    }

    It 'emits no tool property name the MCP client would reject' {
        # MCP property names must match ^[a-zA-Z0-9_.-]{1,64}$ and a single violation is
        # fatal to the WHOLE tools/list, not just the tool that carries it - the client
        # answers 400 and every tool disappears. CIPP endpoints read OData options straight
        # off the request ($Request.Query.'$filter'), so this is one careless entrypoint away
        # at any time. Get-CippMcpSafePropertyName renames them; this proves none escape.
        $Offenders = foreach ($Tool in $script:Tools) {
            foreach ($Key in $Tool.inputSchema.properties.Keys) {
                if ($Key -cnotmatch '^[a-zA-Z0-9_.-]{1,64}$') { "$($Tool.name).$Key" }
            }
        }
        @($Offenders) -join ', ' | Should -BeNullOrEmpty
    }

    It 'renames OData options rather than dropping them' {
        # ListGraphRequest is the model's escape hatch to arbitrary Graph; losing $filter
        # and $select would leave it able to fetch a collection but never narrow it.
        $Graph = @($script:Tools | Where-Object { $_.name -eq 'ListGraphRequest' })[0]
        $Graph | Should -Not -BeNullOrEmpty
        $Graph.inputSchema.properties.Keys | Should -Contain 'odata_filter'
        $Graph.inputSchema.properties.Keys | Should -Contain 'odata_select'
        $Graph._paramAlias['odata_filter'] | Should -Be '$filter'
        # '$expand' and 'expand' are different parameters on this endpoint and must stay distinct
        $Graph.inputSchema.properties.Keys | Should -Contain 'expand'
        $Graph._paramAlias['odata_expand'] | Should -Be '$expand'
    }

    It 'contains the passthrough tools the gateway advertises directly' {
        # Get-CippMcpToolList promotes these two by name. If one is renamed, or its role stops
        # being .Read, the gateway quietly loses its Graph escape hatch or its only way of
        # resolving a tenant - and every other tool needs a tenantFilter.
        foreach ($Name in 'ListTenants', 'ListGraphRequest') {
            $script:Tools.name | Should -Contain $Name -Because "the gateway advertises $Name directly"
        }
    }

    It 'advertises a gateway whose schemas the client will accept' {
        $Gateway = @(Get-CippMcpToolList -Request ([pscustomobject]@{ Query = @{} }) -InformationAction SilentlyContinue)
        @($Gateway.name) | Should -Contain 'SearchTools'
        $Offenders = foreach ($Tool in $Gateway) {
            foreach ($Key in $Tool.inputSchema.properties.Keys) {
                if ($Key -cnotmatch '^[a-zA-Z0-9_.-]{1,64}$') { "$($Tool.name).$Key" }
            }
        }
        @($Offenders) -join ', ' | Should -BeNullOrEmpty
    }
}

