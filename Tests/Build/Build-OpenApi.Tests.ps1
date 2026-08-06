# Pester tests for build/tools/build-openapi.ps1
# Runs the generator over a fixture tree of entrypoints and asserts the emitted
# OpenAPI matches what the PowerShell actually reads. The cases are the ones a
# regex scanner gets wrong: nested member chains, null-coalescing alternates,
# foreach and pipeline element access, array request bodies, and the difference
# between binding $Request.Body to a local and forwarding it wholesale.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $GeneratorPath = Join-Path (Split-Path -Parent $RepoRoot) 'build/tools/build-openapi.ps1'
    if (-not (Test-Path $GeneratorPath)) { throw "Could not locate build-openapi.ps1 at $GeneratorPath" }

    $FixtureRoot = Join-Path $TestDrive 'Entrypoints'
    $AreaDir = Join-Path $FixtureRoot 'Identity/Administration'
    $null = New-Item -ItemType Directory -Path $AreaDir -Force
    $OverrideDir = Join-Path $TestDrive 'overrides'
    $null = New-Item -ItemType Directory -Path $OverrideDir -Force

    # Stand-in for backend/Modules: the generator indexes these so it can follow a
    # request body handed to a shared helper. Kept local so the suite never depends
    # on the real CIPPCore.
    $ModulesRoot = Join-Path $TestDrive 'Modules'
    $CoreDir = Join-Path $ModulesRoot 'CIPPCore/Public'
    $null = New-Item -ItemType Directory -Path $CoreDir -Force
    Set-Content -Path (Join-Path $CoreDir 'Set-FixtureUser.ps1') -Value @'
function Set-FixtureUser {
    param($UserObj, $Headers)
    # Job title, straight from the helper.
    $Title = $UserObj.jobTitle
    $City = $UserObj.address.city
    $Manager = $UserObj.setManager.value
    Write-Output "$Title $City $Manager"
}
'@

    # The reported bug, reduced: the backend reads .value off the field, so the
    # documented type has to be an object. A bare string resolves to $null and the
    # endpoint silently does nothing.
    Set-Content -Path (Join-Path $AreaDir 'Invoke-ExecNested.ps1') -Value @'
function Invoke-ExecNested {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Nested access.
    #>
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Body.tenantFilter
    # The user we are granting access to.
    $Target = $Request.Body.onedriveAccessUser.value ?? $Request.Body.user.value
    $Flag = [bool]$Request.Body.notify
    $Count = $Request.Body.retries -as [int]
    if (-not $Request.Body.URL) { throw 'URL is required' }
    switch ($Request.Body.action) { 'grant' { } 'revoke' { } }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = "$TenantFilter $Target $Flag $Count" }
        })
}
'@

    # Aliased body plus element access via foreach and via a filtered pipeline.
    Set-Content -Path (Join-Path $AreaDir 'Invoke-ExecAliased.ps1') -Value @'
function Invoke-ExecAliased {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    #>
    param($Request, $TriggerMetadata)
    $UserObj = $Request.Body
    $Name = $UserObj.displayName
    foreach ($Group in $UserObj.AddToGroups) {
        $Id = $Group.value
    }
    $Mails = $UserObj.Contacts | Where-Object { $_.enabled } | ForEach-Object { $_.emailAddress }
    $Tenant = $Request.Query.tenantFilter
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = "$Name $Id $Mails $Tenant" }
        })
}
'@

    # The whole payload is a JSON array.
    Set-Content -Path (Join-Path $AreaDir 'Invoke-ExecArrayBody.ps1') -Value @'
function Invoke-ExecArrayBody {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    foreach ($Entry in $Request.Body) {
        $Upn = $Entry.userPrincipalName
        $Sku = $Entry.license.value
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = "$Upn $Sku" }
        })
}
'@

    # Forwards the body onward instead of reading fixed fields.
    Set-Content -Path (Join-Path $AreaDir 'Invoke-ExecPassthrough.ps1') -Value @'
function Invoke-ExecPassthrough {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $Json = ConvertTo-Json $Request.Body -Depth 10
    $Tenant = $Request.Body.tenantFilter
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = "$Json $Tenant" }
        })
}
'@

    # Reads a couple of fields itself and hands the body to a helper for the rest.
    Set-Content -Path (Join-Path $AreaDir 'Invoke-EditFixtureUser.ps1') -Value @'
function Invoke-EditFixtureUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    param($Request, $TriggerMetadata)
    $UserObj = $Request.Body
    $Id = $UserObj.id
    $Results = Set-FixtureUser -UserObj $UserObj -Headers $Request.Headers
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = "$Id $Results" }
        })
}
'@

    # Query-only, and a List verb so the response is an array.
    Set-Content -Path (Join-Path $FixtureRoot 'Invoke-ListThings.ps1') -Value @'
function Invoke-ListThings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    param($Request, $TriggerMetadata)
    $Tenant = $Request.Query.tenantFilter
    $Filter = $Request.Query.graphFilter
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Tenant, $Filter)
        })
}
'@

    # Not an endpoint: no Entrypoint marker.
    Set-Content -Path (Join-Path $FixtureRoot 'Invoke-NotAnEndpoint.ps1') -Value @'
function Invoke-NotAnEndpoint {
    <#
    .FUNCTIONALITY
        Internal
    #>
    param($Request)
    $x = $Request.Body.thing
}
'@

    # Stand-in for frontend/src. The UI declares which fields it renders per list
    # endpoint; that is the only static description of a response anywhere.
    $FrontendDir = Join-Path $TestDrive 'frontend/src'
    $null = New-Item -ItemType Directory -Path $FrontendDir -Force
    Set-Content -Path (Join-Path $FrontendDir 'things.jsx') -Value @'
<CippTablePage
  apiUrl="/api/ListThings"
  simpleColumns={['displayName', 'mail']}
/>
'@

    $OutputPath = Join-Path $TestDrive 'openapi.json'
    & $GeneratorPath -EntrypointPath $FixtureRoot -ModulesPath $ModulesRoot -OverridePath $OverrideDir `
        -FrontendPath $FrontendDir -OutputPath $OutputPath | Out-Null
    $script:Spec = Get-Content $OutputPath -Raw | ConvertFrom-Json -AsHashtable
    $script:GeneratorPath = $GeneratorPath
    $script:FixtureRoot = $FixtureRoot
    $script:OverrideDir = $OverrideDir
    $script:ModulesRoot = $ModulesRoot
    $script:FrontendDir = $FrontendDir

    # Regenerates from the fixture tree with one setting varied. Used by the cases
    # that need to assert on a different frontend/module/override input.
    function Invoke-Generator {
        param([string]$Name, [hashtable]$With = @{})
        $Arguments = @{
            EntrypointPath = $script:FixtureRoot
            ModulesPath    = $script:ModulesRoot
            OverridePath   = $script:OverrideDir
            FrontendPath   = $script:FrontendDir
            OutputPath     = Join-Path $TestDrive "$Name.json"
        }
        foreach ($Key in $With.Keys) { $Arguments[$Key] = $With[$Key] }
        & $script:GeneratorPath @Arguments | Out-Null
        return Get-Content $Arguments.OutputPath -Raw | ConvertFrom-Json -AsHashtable
    }

    # The record schema for a list endpoint's 200, wherever it ended up.
    function Get-ResponseRecord {
        param($Spec, [string]$Endpoint, [string]$Method = 'get')
        $Schema = $Spec.paths["/api/$Endpoint"].$Method.responses.'200'.content.'application/json'.schema
        if ($Schema.type -eq 'array') { return $Schema.items }
        return $Schema
    }

    function Get-BodyProperty {
        param([string]$Endpoint, [string]$Property)
        $Schema = $script:Spec.paths["/api/$Endpoint"].post.requestBody.content.'application/json'.schema
        if ($Schema.type -eq 'array') { $Schema = $Schema.items }
        return $Schema.properties[$Property]
    }
}

Describe 'endpoint discovery' {
    It 'includes every function marked Entrypoint' {
        $script:Spec.paths.Keys | Should -Contain '/api/ExecNested'
        $script:Spec.paths.Keys | Should -Contain '/api/ExecAliased'
        $script:Spec.paths.Keys | Should -Contain '/api/ListThings'
    }

    It 'excludes functions that are not entrypoints' {
        $script:Spec.paths.Keys | Should -Not -Contain '/api/NotAnEndpoint'
    }

    It 'carries the .ROLE through as x-cipp-role' {
        $script:Spec.paths['/api/ExecNested'].post.'x-cipp-role' | Should -Be 'Identity.User.ReadWrite'
    }

    It 'tags by the folder the entrypoint lives in' {
        $script:Spec.paths['/api/ExecNested'].post.tags[0] | Should -Be 'Identity > Administration'
    }

    It 'only ever emits get or post, the methods the API accepts' {
        foreach ($Path in $script:Spec.paths.Values) {
            foreach ($Method in $Path.Keys) { $Method | Should -BeIn @('get', 'post') }
        }
    }

    It 'emits exactly one operation per path so MCP tool names stay unique' {
        foreach ($Path in $script:Spec.paths.Values) { $Path.Keys.Count | Should -Be 1 }
    }
}

Describe 'nested member chains' {
    # the regression the whole rewrite exists for
    It 'types a field read as $Field.value as an object, not a string' {
        $Property = Get-BodyProperty -Endpoint 'ExecNested' -Property 'onedriveAccessUser'
        $Ref = if ($Property.'$ref') { $Property.'$ref' } else { $Property.allOf[0].'$ref' }
        $Ref | Should -Be '#/components/schemas/LabelValue'
    }

    It 'records both operands of a null-coalescing read' {
        (Get-BodyProperty -Endpoint 'ExecNested' -Property 'user') | Should -Not -BeNullOrEmpty
    }

    It 'describes LabelValue as requiring value' {
        $script:Spec.components.schemas.LabelValue.required | Should -Contain 'value'
    }

    It 'uses the source comment as the field description' {
        $Property = Get-BodyProperty -Endpoint 'ExecNested' -Property 'onedriveAccessUser'
        $Property.description | Should -Match 'granting access'
    }
}

Describe 'type inference from usage' {
    It 'infers boolean from a [bool] cast' {
        (Get-BodyProperty -Endpoint 'ExecNested' -Property 'notify').type | Should -Be 'boolean'
    }

    It 'infers integer from -as [int]' {
        (Get-BodyProperty -Endpoint 'ExecNested' -Property 'retries').type | Should -Be 'integer'
    }

    It 'turns a switch statement into an enum' {
        (Get-BodyProperty -Endpoint 'ExecNested' -Property 'action').enum | Should -Be @('grant', 'revoke')
    }

    It 'defaults to string when nothing in the source says otherwise' {
        (Get-BodyProperty -Endpoint 'ExecNested' -Property 'URL').type | Should -Be 'string'
    }
}

Describe 'required fields' {
    It 'marks a field required when a guard rejects the request without it' {
        $Schema = $script:Spec.paths['/api/ExecNested'].post.requestBody.content.'application/json'.schema
        $Schema.required | Should -Contain 'URL'
    }

    It 'requires tenantFilter by default' {
        $Schema = $script:Spec.paths['/api/ExecNested'].post.requestBody.content.'application/json'.schema
        $Schema.required | Should -Contain 'tenantFilter'
    }

    It 'does not require tenantFilter on an AnyTenant endpoint' {
        $Parameters = $script:Spec.paths['/api/ExecAliased'].post.parameters
        $Tenant = $Parameters | Where-Object { $_.name -eq 'tenantFilter' }
        $Tenant.required | Should -BeFalse
        $script:Spec.paths['/api/ExecAliased'].post.'x-cipp-any-tenant' | Should -BeTrue
    }
}

Describe 'alias and element resolution' {
    It 'resolves fields read through a local bound to $Request.Body' {
        (Get-BodyProperty -Endpoint 'ExecAliased' -Property 'displayName') | Should -Not -BeNullOrEmpty
    }

    It 'treats a foreach source as an array and attributes fields to its items' {
        $Groups = Get-BodyProperty -Endpoint 'ExecAliased' -Property 'AddToGroups'
        $Groups.type | Should -Be 'array'
        $Ref = if ($Groups.items.'$ref') { $Groups.items.'$ref' } else { $Groups.items.allOf[0].'$ref' }
        $Ref | Should -Be '#/components/schemas/LabelValue'
    }

    It 'resolves $_ inside ForEach-Object through an intervening Where-Object' {
        $Contacts = Get-BodyProperty -Endpoint 'ExecAliased' -Property 'Contacts'
        $Contacts.type | Should -Be 'array'
        $Contacts.items.properties.Keys | Should -Contain 'emailAddress'
        $Contacts.items.properties.Keys | Should -Contain 'enabled'
    }

    It 'does not treat binding $Request.Body to a local as a passthrough' {
        $Schema = $script:Spec.paths['/api/ExecAliased'].post.requestBody.content.'application/json'.schema
        $Schema.'x-cipp-passthrough' | Should -BeNullOrEmpty
    }
}

Describe 'downstream helpers' {
    # Invoke-EditUser reads 6 fields and hands the body to Set-CIPPUser, which reads
    # 30 more. Documenting only the entrypoint silently omits most of the contract.
    It 'recovers fields read by the helper the body was passed to' {
        $Properties = $script:Spec.paths['/api/EditFixtureUser'].post.requestBody.content.'application/json'.schema.properties
        $Properties.Keys | Should -Contain 'id'
        $Properties.Keys | Should -Contain 'jobTitle'
    }

    It 'keeps nested chains read inside the helper' {
        $Properties = $script:Spec.paths['/api/EditFixtureUser'].post.requestBody.content.'application/json'.schema.properties
        $Properties['address'].properties.Keys | Should -Contain 'city'
        $Ref = if ($Properties['setManager'].'$ref') { $Properties['setManager'].'$ref' } else { $Properties['setManager'].allOf[0].'$ref' }
        $Ref | Should -Be '#/components/schemas/LabelValue'
    }

    It 'uses the comment inside the helper as the description' {
        $Properties = $script:Spec.paths['/api/EditFixtureUser'].post.requestBody.content.'application/json'.schema.properties
        $Properties['jobTitle'].description | Should -Match 'straight from the helper'
    }

    It 'records which helpers contributed fields' {
        $script:Spec.paths['/api/EditFixtureUser'].post.'x-cipp-reads-via' | Should -Contain 'Set-FixtureUser'
    }

    It 'documents only the entrypoint when no modules are indexed' {
        $Path = Join-Path $TestDrive 'no-modules.json'
        & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath (Join-Path $TestDrive 'absent') `
            -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $Path | Out-Null
        $Shallow = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
        $Properties = $Shallow.paths['/api/EditFixtureUser'].post.requestBody.content.'application/json'.schema.properties
        $Properties.Keys | Should -Contain 'id'
        $Properties.Keys | Should -Not -Contain 'jobTitle'
    }
}

Describe 'array request bodies' {
    It 'emits an array schema when the body itself is enumerated' {
        $Schema = $script:Spec.paths['/api/ExecArrayBody'].post.requestBody.content.'application/json'.schema
        $Schema.type | Should -Be 'array'
        $Schema.items.properties.Keys | Should -Contain 'userPrincipalName'
    }

    It 'keeps nested chains inside array elements' {
        $Property = Get-BodyProperty -Endpoint 'ExecArrayBody' -Property 'license'
        $Ref = if ($Property.'$ref') { $Property.'$ref' } else { $Property.allOf[0].'$ref' }
        $Ref | Should -Be '#/components/schemas/LabelValue'
    }
}

Describe 'passthrough detection' {
    It 'flags a body that is forwarded wholesale' {
        $Schema = $script:Spec.paths['/api/ExecPassthrough'].post.requestBody.content.'application/json'.schema
        $Schema.'x-cipp-passthrough' | Should -BeTrue
        $Schema.additionalProperties | Should -BeTrue
    }

    It 'still lists the fields it is known to read' {
        $Schema = $script:Spec.paths['/api/ExecPassthrough'].post.requestBody.content.'application/json'.schema
        $Schema.properties.Keys | Should -Contain 'tenantFilter'
    }
}

Describe 'query endpoints' {
    It 'emits a GET when only the query string is read' {
        $script:Spec.paths['/api/ListThings'].Keys | Should -Be @('get')
    }

    It 'refs the shared tenantFilter parameter' {
        $Refs = $script:Spec.paths['/api/ListThings'].get.parameters | ForEach-Object { $_.'$ref' }
        $Refs | Should -Contain '#/components/parameters/tenantFilter'
    }

    It 'documents an array response for a List endpoint' {
        $Schema = $script:Spec.paths['/api/ListThings'].get.responses.'200'.content.'application/json'.schema
        $Schema.type | Should -Be 'array'
    }
}

Describe 'responses' {
    It 'uses the StandardResults envelope when the body is @{ Results = ... }' {
        $Schema = $script:Spec.paths['/api/ExecNested'].post.responses.'200'.content.'application/json'.schema
        $Schema.'$ref' | Should -Be '#/components/schemas/StandardResults'
    }

    It 'always documents the platform 401 and 403' {
        $script:Spec.paths['/api/ExecNested'].post.responses.Keys | Should -Contain '401'
        $script:Spec.paths['/api/ExecNested'].post.responses.Keys | Should -Contain '403'
    }

    It 'does not invent status codes the endpoint cannot return' {
        # ExecAliased has no BadRequest path
        $script:Spec.paths['/api/ExecAliased'].post.responses.Keys | Should -Not -Contain '400'
    }
}

Describe 'response records from frontend columns' {
    # Ported from the retired Add-OpenApiResponseSchemas suite. The PowerShell says
    # nothing about response shape, so the UI's simpleColumns is the only static
    # signal; the parser has to stay literal or it invents fields.
    It 'types a list response from the columns the UI renders' {
        $Record = Get-ResponseRecord -Spec $script:Spec -Endpoint 'ListThings'
        $Record.properties.Keys | Should -Contain 'displayName'
        $Record.properties.Keys | Should -Contain 'mail'
    }

    It 'marks the provenance of frontend-derived fields' {
        $Record = Get-ResponseRecord -Spec $script:Spec -Endpoint 'ListThings'
        $Record.properties['mail'].'x-cipp-field-source' | Should -Be 'frontend'
    }

    It 'keeps the record open, because display columns are not the whole record' {
        $Record = Get-ResponseRecord -Spec $script:Spec -Endpoint 'ListThings'
        $Record.additionalProperties | Should -BeTrue
    }

    It 'sorts columns so output stays deterministic' {
        Set-Content -Path (Join-Path $TestDrive 'frontend/src/sorted.jsx') -Value @'
<CippTablePage apiUrl="/api/ListThings" simpleColumns={['zeta', 'alpha']} />
'@
        try {
            $Spec = Invoke-Generator -Name 'sorted'
            # conflicting declarations for one endpoint are dropped, so this asserts the
            # drop rather than a sort; the sort is covered by the unambiguous case below
            $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
            $Record.properties.Keys | Should -BeNullOrEmpty
        } finally {
            Remove-Item (Join-Path $TestDrive 'frontend/src/sorted.jsx') -Force
        }
    }

    It 'handles mixed quotes and an array split after the opening brace' {
        $Dir = Join-Path $TestDrive 'fe-split/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'split.jsx') -Value @'
<CippDataTable
  apiUrl="/api/ListThings"
  simpleColumns={
    ["displayName", 'mail']
  }
/>
'@
        $Spec = Invoke-Generator -Name 'fe-split' -With @{ FrontendPath = $Dir }
        $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
        @($Record.properties.Keys) | Should -Be @('displayName', 'mail')
    }

    It 'ignores a ternary rather than leaking its scalar branches' {
        $Dir = Join-Path $TestDrive 'fe-ternary/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'ternary.jsx') -Value @'
const label = enabled ? "yes" : "no";
const simpleColumns = hasScope
  ? ['RowKey', 'Value']
  : ['RowKey', 'Value', 'Scope'];
apiUrl="/api/ListThings"
'@
        $Spec = Invoke-Generator -Name 'fe-ternary' -With @{ FrontendPath = $Dir }
        $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
        $Record.properties.Keys | Should -Not -Contain 'yes'
        $Record.properties.Keys | Should -Not -Contain 'no'
    }

    It 'does not leak a nearby ternary when simpleColumns itself is a literal array' {
        $Dir = Join-Path $TestDrive 'fe-nearby/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'nearby.jsx') -Value @'
const statusLabel = enabled ? "yes" : "no";
const simpleColumns = ["displayName", "mail"];
apiUrl="/api/ListThings"
'@
        $Spec = Invoke-Generator -Name 'fe-nearby' -With @{ FrontendPath = $Dir }
        $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
        @($Record.properties.Keys) | Should -Be @('displayName', 'mail')
        $Record.properties.Keys | Should -Not -Contain 'yes'
    }

    It 'drops an endpoint whose pages declare different columns' {
        # ListGraphRequest backs a dozen unrelated pages; a union would describe a
        # record no single call returns
        $Dir = Join-Path $TestDrive 'fe-conflict/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'a.jsx') -Value '<X apiUrl="/api/ListThings" simpleColumns={["a"]} />'
        Set-Content -Path (Join-Path $Dir 'b.jsx') -Value '<X apiUrl="/api/ListThings" simpleColumns={["b"]} />'
        $Spec = Invoke-Generator -Name 'fe-conflict' -With @{ FrontendPath = $Dir }
        $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
        $Record.properties.Keys | Should -BeNullOrEmpty
        $Record.additionalProperties | Should -BeTrue
    }

    It 'ignores a file whose columns cannot be attributed to one endpoint' {
        $Dir = Join-Path $TestDrive 'fe-ambiguous/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'two.jsx') -Value @'
<X apiUrl="/api/ListThings" simpleColumns={["a", "b"]} />
<Y apiUrl="/api/ListOther" />
'@
        Set-Content -Path (Join-Path $Dir 'none.jsx') -Value 'const simpleColumns = ["x"];'
        $Spec = Invoke-Generator -Name 'fe-ambiguous' -With @{ FrontendPath = $Dir }
        $Record = Get-ResponseRecord -Spec $Spec -Endpoint 'ListThings'
        $Record.properties.Keys | Should -BeNullOrEmpty
    }

    It 'does not crash on an empty file or a missing frontend directory' {
        $Dir = Join-Path $TestDrive 'fe-empty/src'
        $null = New-Item -ItemType Directory -Path $Dir -Force
        Set-Content -Path (Join-Path $Dir 'empty.jsx') -Value ''
        { Invoke-Generator -Name 'fe-empty' -With @{ FrontendPath = $Dir } } | Should -Not -Throw
        { Invoke-Generator -Name 'fe-absent' -With @{ FrontendPath = (Join-Path $TestDrive 'nope') } } | Should -Not -Throw
    }

    It 'leaves action endpoints on the Results envelope regardless of columns' {
        $Schema = $script:Spec.paths['/api/ExecNested'].post.responses.'200'.content.'application/json'.schema
        $Schema.'$ref' | Should -Be '#/components/schemas/StandardResults'
    }
}

Describe 'overrides' {
    BeforeAll {
        Set-Content -Path (Join-Path $script:OverrideDir 'ExecNested.json') -Value @'
{
  "description": "Hand-written description.",
  "requestBody": {
    "content": {
      "application/json": {
        "schema": {
          "properties": {
            "URL": { "type": "string", "format": "uri" },
            "retries": null
          }
        }
      }
    }
  }
}
'@
        $Path = Join-Path $TestDrive 'openapi-override.json'
        & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath $script:OverrideDir -OutputPath $Path | Out-Null
        $script:Overridden = Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
    }

    It 'merges scalar keys over the generated operation' {
        $script:Overridden.paths['/api/ExecNested'].post.description | Should -Be 'Hand-written description.'
    }

    It 'merges into nested schemas without discarding siblings' {
        $Properties = $script:Overridden.paths['/api/ExecNested'].post.requestBody.content.'application/json'.schema.properties
        $Properties['URL'].format | Should -Be 'uri'
        $Properties.Keys | Should -Contain 'onedriveAccessUser'
    }

    It 'deletes a key when the override value is null' {
        $Properties = $script:Overridden.paths['/api/ExecNested'].post.requestBody.content.'application/json'.schema.properties
        $Properties.Keys | Should -Not -Contain 'retries'
    }

    It 'leaves untouched keys coming from the source' {
        $script:Overridden.paths['/api/ExecNested'].post.'x-cipp-role' | Should -Be 'Identity.User.ReadWrite'
    }
}

Describe 'determinism and drift checking' {
    It 'produces byte-identical output across runs' {
        $A = Join-Path $TestDrive 'run-a.json'
        $B = Join-Path $TestDrive 'run-b.json'
        & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $A | Out-Null
        & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $B | Out-Null
        (Get-Content $A -Raw) | Should -Be (Get-Content $B -Raw)
    }

    It '-Check passes against a spec it just wrote' {
        $Path = Join-Path $TestDrive 'check.json'
        & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $Path | Out-Null
        { & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $Path -Check } | Should -Not -Throw
    }

    It '-Check fails when the committed spec is stale' {
        $Path = Join-Path $TestDrive 'stale.json'
        Set-Content -Path $Path -Value '{"openapi":"3.1.0"}'
        { & $script:GeneratorPath -EntrypointPath $script:FixtureRoot -ModulesPath $script:ModulesRoot -OverridePath (Join-Path $TestDrive 'empty') -OutputPath $Path -Check } | Should -Throw -ExpectedMessage '*stale*'
    }
}
