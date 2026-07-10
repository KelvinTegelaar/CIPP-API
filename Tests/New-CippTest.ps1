#Requires -Version 7.0
<#
.SYNOPSIS
    Scaffolds a Pester test for a CIPP-API backend function.

.DESCRIPTION
    Locates a function by name under Modules/, parses it with the PowerShell AST, and
    emits a starter <name>.Tests.ps1 under Tests/<Area>/ that already contains:
      * a move-resilient path resolver (find the function by filename, never hardcode a module),
      * stub functions for every CIPP helper the function calls (so Pester Mock can replace them),
      * fake HttpResponseContext / HttpRequestContext classes for HTTP endpoints,
      * a Describe block with placeholder It cases (happy path + one per required field),
    each marked with # TODO where a human or Claude fills in real assertions.

    It deliberately does NOT try to write meaningful assertions - that requires reading the
    function's intent. The goal is to remove the ~30 lines of boilerplate and dependency
    guesswork, then hand a runnable skeleton to the author.

.PARAMETER FunctionName
    The function to scaffold a test for, e.g. Invoke-ListIntuneReusableSettings.

.PARAMETER Force
    Overwrite an existing test file.

.PARAMETER Area
    Override the auto-detected Tests/ subfolder (Endpoint, Standards, Alerts, Private).

.EXAMPLE
    pwsh CIPP-API/Tests/New-CippTest.ps1 -FunctionName Invoke-ListIntuneReusableSettings
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$FunctionName,

    [switch]$Force,

    [ValidateSet('Endpoint', 'Standards', 'Alerts', 'Private')]
    [string]$Area
)

$ErrorActionPreference = 'Stop'

$TestsRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $TestsRoot
$ModulesRoot = Join-Path $RepoRoot 'Modules'

# --- 1. Locate the function file by name (this is what avoids hardcoded, rot-prone paths) ---
$matches = @(Get-ChildItem -Path $ModulesRoot -Recurse -Filter "$FunctionName.ps1" -File -ErrorAction SilentlyContinue)
if ($matches.Count -eq 0) {
    throw "No file named '$FunctionName.ps1' found under $ModulesRoot. Check the function name."
}
if ($matches.Count -gt 1) {
    $list = ($matches.FullName | ForEach-Object { "  $_" }) -join "`n"
    throw "Multiple files named '$FunctionName.ps1' found - cannot disambiguate:`n$list"
}
$FunctionFile = $matches[0].FullName

# --- 2. Parse with the AST ---
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionFile, [ref]$tokens, [ref]$parseErrors)

$funcAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $FunctionName
    }, $true)
if (-not $funcAst) {
    throw "File '$FunctionFile' does not define a function called '$FunctionName'."
}

# Endpoint detection: HTTP entrypoints take $Request and $TriggerMetadata.
$paramNames = @()
if ($funcAst.Body.ParamBlock) {
    $paramNames = $funcAst.Body.ParamBlock.Parameters.Name.VariablePath.UserPath
}
$isEndpoint = ($paramNames -contains 'Request' -and $paramNames -contains 'TriggerMetadata')

# --- 3. Discover called CIPP helpers (to emit as stubbable functions) ---
# Only stub commands that look like CIPP helpers; never stub PowerShell built-ins.
$helperPattern = '(?i)(cipp|graph.*request|azdatatable|write-logmessage|write-alert|write-standardsalert|get-normalizederror)'
$commandAsts = $funcAst.FindAll({
        param($node) $node -is [System.Management.Automation.Language.CommandAst]
    }, $true)
$helpers = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($c in $commandAsts) {
    $name = $c.GetCommandName()
    if ($name -and $name -ne $FunctionName -and $name -match $helperPattern) {
        [void]$helpers.Add($name)
    }
}

# --- 4. Discover input fields read from $Request.Body.* / $Request.Query.* ---
# Track which container each field comes from so the happy-path request seeds the right bag.
$bodyFields = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queryFields = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($isEndpoint) {
    $memberAsts = $funcAst.FindAll({
            param($node) $node -is [System.Management.Automation.Language.MemberExpressionAst]
        }, $true)
    foreach ($m in $memberAsts) {
        $inner = $m.Expression
        if ($inner -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $inner.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $inner.Expression.VariablePath.UserPath -eq 'Request' -and
            $inner.Member.Value -in @('Body', 'Query') -and
            $m.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $field = $m.Member.Value
            if ($inner.Member.Value -eq 'Body') { [void]$bodyFields.Add($field) }
            else { [void]$queryFields.Add($field) }
        }
    }
}
$usesBody = $bodyFields.Count -gt 0
$usesQuery = $queryFields.Count -gt 0

# --- 5. Discover required-field guards from '<field> is required' literals ---
$requiredFields = [System.Collections.Generic.List[string]]::new()
$strings = $funcAst.FindAll({
        param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true)
foreach ($s in $strings) {
    if ($s.Value -match '^(\w+)\s+is required') {
        if (-not $requiredFields.Contains($Matches[1])) { $requiredFields.Add($Matches[1]) }
    }
}

# --- 6. Determine the Area (Tests/ subfolder) ---
if (-not $Area) {
    $rel = $FunctionFile.Substring($ModulesRoot.Length).Replace('\', '/')
    $Area = switch -Regex ($rel) {
        'Entrypoints/HTTP Functions' { 'Endpoint'; break }
        '/Standards/' { 'Standards'; break }
        '/Alerts/' { 'Alerts'; break }
        default { 'Private' }
    }
}
$OutDir = Join-Path $TestsRoot $Area
$OutFile = Join-Path $OutDir "$FunctionName.Tests.ps1"
if ((Test-Path $OutFile) -and -not $Force) {
    throw "Test already exists: $OutFile (use -Force to overwrite)."
}

# --- 7. Build the test file content ---
$nl = "`n"
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append("# Pester tests for $FunctionName$nl")
[void]$sb.Append("# Scaffolded by New-CippTest.ps1 - replace every # TODO with real assertions.$nl$nl")
[void]$sb.Append("BeforeAll {$nl")
[void]$sb.Append("    # Resolve by name under Modules/ so the test survives the function moving between modules.$nl")
[void]$sb.Append("    `$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent `$PSCommandPath))$nl")
[void]$sb.Append("    `$FunctionPath = Get-ChildItem -Path (Join-Path `$RepoRoot 'Modules') -Recurse -Filter '$FunctionName.ps1' -File -ErrorAction SilentlyContinue |$nl")
[void]$sb.Append("        Select-Object -First 1 -ExpandProperty FullName$nl")
[void]$sb.Append("    if (-not `$FunctionPath) { throw 'Could not locate $FunctionName.ps1 under Modules/' }$nl$nl")

if ($isEndpoint) {
    [void]$sb.Append("    # Azure Functions binding types do not exist outside the Functions host - fake them.$nl")
    [void]$sb.Append("    class HttpResponseContext {$nl        [int]`$StatusCode$nl        [object]`$Body$nl    }$nl$nl")
}

if ($helpers.Count -gt 0) {
    [void]$sb.Append("    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.$nl")
    foreach ($h in $helpers) {
        [void]$sb.Append("    function $h { }$nl")
    }
    [void]$sb.Append($nl)
}

[void]$sb.Append("    . `$FunctionPath$nl")
[void]$sb.Append("}$nl$nl")

[void]$sb.Append("Describe '$FunctionName' {$nl")
[void]$sb.Append("    BeforeEach {$nl")
foreach ($h in $helpers) {
    [void]$sb.Append("        Mock -CommandName $h -MockWith { } # TODO: return realistic data / capture args$nl")
}
[void]$sb.Append("    }$nl$nl")

if ($isEndpoint) {
    # Render a container literal (Body/Query) seeded with the fields it actually exposes.
    function Format-Container {
        param([System.Collections.Generic.SortedSet[string]]$Fields)
        $pairs = foreach ($f in $Fields) {
            if ($f -ieq 'tenantFilter') { "$f = 'contoso.onmicrosoft.com'" } else { "$f = 'TODO'" }
        }
        '[pscustomobject]@{ ' + ($pairs -join '; ') + ' }'
    }

    # Happy-path case with a sample request built from discovered input fields.
    [void]$sb.Append("    It 'returns OK on the happy path' {$nl")
    [void]$sb.Append("        `$request = [pscustomobject]@{$nl")
    [void]$sb.Append("            Params  = @{ CIPPEndpoint = '$($FunctionName -replace '^Invoke-', '')' }$nl")
    [void]$sb.Append("            Headers = @{ Authorization = 'token' }$nl")
    if ($usesBody) {
        [void]$sb.Append("            Body    = $(Format-Container $bodyFields)$nl")
    }
    if ($usesQuery) {
        [void]$sb.Append("            Query   = $(Format-Container $queryFields)$nl")
    }
    [void]$sb.Append("        }$nl$nl")
    [void]$sb.Append("        `$response = $FunctionName -Request `$request -TriggerMetadata `$null$nl$nl")
    [void]$sb.Append("        `$response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)$nl")
    [void]$sb.Append("        # TODO: assert `$response.Body and Should -Invoke the helpers with -ParameterFilter$nl")
    [void]$sb.Append("    }$nl")

    # Negative cases: endpoints validate required fields in order, so an all-empty request
    # would always trip the FIRST guard. Instead start from a baseline that satisfies every
    # guard, then drop ONLY the field under test so its specific guard is the one that fires.
    function Get-FieldContainer {
        param([string]$Field)
        if ($bodyFields.Contains($Field)) { 'Body' } elseif ($queryFields.Contains($Field)) { 'Query' } else { 'Body' }
    }
    function Format-RequiredRequest {
        param([string]$Omit)
        $bodyPairs = [System.Collections.Generic.List[string]]::new()
        $queryPairs = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $requiredFields) {
            if ($f -ieq $Omit) { continue }
            $val = if ($f -ieq 'tenantFilter') { "'contoso.onmicrosoft.com'" } else { "'TODO'" }
            if ((Get-FieldContainer $f) -eq 'Body') { $bodyPairs.Add("$f = $val") } else { $queryPairs.Add("$f = $val") }
        }
        $b = '[pscustomobject]@{' + $(if ($bodyPairs.Count) { ' ' + ($bodyPairs -join '; ') + ' ' } else { '' }) + '}'
        $q = '[pscustomobject]@{' + $(if ($queryPairs.Count) { ' ' + ($queryPairs -join '; ') + ' ' } else { '' }) + '}'
        "Body = $b ; Query = $q"
    }

    foreach ($field in $requiredFields) {
        [void]$sb.Append($nl)
        [void]$sb.Append("    It 'returns BadRequest when $field is missing' {$nl")
        [void]$sb.Append("        # Baseline has every other required field populated; only $field is dropped.$nl")
        [void]$sb.Append("        `$request = [pscustomobject]@{ $(Format-RequiredRequest -Omit $field) }$nl")
        [void]$sb.Append("        `$response = $FunctionName -Request `$request -TriggerMetadata `$null$nl$nl")
        [void]$sb.Append("        `$response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)$nl")
        [void]$sb.Append("        `$response.Body.Results | Should -Match '$field is required'$nl")
        [void]$sb.Append("    }$nl")
    }
} else {
    # Non-endpoint function: emit a single placeholder invocation case.
    $callParams = ($paramNames | ForEach-Object { "-$_ `$null" }) -join ' '
    [void]$sb.Append("    It 'does the expected thing' {$nl")
    [void]$sb.Append("        # TODO: call with realistic arguments and assert behaviour$nl")
    [void]$sb.Append("        # $FunctionName $callParams$nl")
    [void]$sb.Append("        `$true | Should -BeTrue # TODO: replace$nl")
    [void]$sb.Append("    }$nl")
}

[void]$sb.Append("}$nl")

# --- 8. Write it out ---
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
Set-Content -Path $OutFile -Value $sb.ToString() -Encoding utf8 -NoNewline

Write-Host "Scaffolded: $OutFile" -ForegroundColor Green
Write-Host "  Function : $FunctionFile"
Write-Host "  Area     : $Area  |  Endpoint: $isEndpoint"
Write-Host "  Helpers  : $(if ($helpers.Count) { $helpers -join ', ' } else { '(none detected)' })"
if ($isEndpoint) {
    Write-Host "  Body     : $(if ($bodyFields.Count) { $bodyFields -join ', ' } else { '(none)' })"
    Write-Host "  Query    : $(if ($queryFields.Count) { $queryFields -join ', ' } else { '(none)' })"
    Write-Host "  Required : $(if ($requiredFields.Count) { $requiredFields -join ', ' } else { '(none)' })"
}
Write-Host "Next: fill in the # TODOs, then run:" -ForegroundColor Cyan
Write-Host "  pwsh $($MyInvocation.MyCommand.Path -replace 'New-CippTest','Invoke-CippTests') -Path `"$([System.IO.Path]::GetRelativePath($RepoRoot, $OutFile))`""
