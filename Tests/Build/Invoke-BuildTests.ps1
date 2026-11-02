#Requires -Version 7.0
<#
.SYNOPSIS
    Runs static analysis and the Pester suites for the build-stage generators.

.DESCRIPTION
    One-command verification for the scripts under build/tools that produce
    generated artifacts shipped in the image: function-parameters.json and
    openapi.json. Checks PSScriptAnalyzer findings for each generator and its
    tests, then runs the Pester suites in this folder. Exits non-zero on failure.

    Write-Host is excluded to match the repository's CI policy: these are build
    scripts whose progress output is the point.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolsRoot = Join-Path (Split-Path -Parent $repoRoot) 'build' 'tools'

$generators = @('build-function-parameters.ps1', 'build-openapi.ps1') |
    ForEach-Object { Join-Path $toolsRoot $_ }

$missing = @($generators | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    throw "Generator script(s) not found: $($missing -join ', ')"
}

$testFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File)

Write-Information 'Running PSScriptAnalyzer...' -InformationAction Continue
$analysisFindings = @(
    foreach ($path in @($generators) + @($testFiles.FullName)) {
        Invoke-ScriptAnalyzer -Path $path -Severity Warning, Error -ExcludeRule PSAvoidUsingWriteHost, PSUseBOMForUnicodeEncodedFile
    }
)

if ($analysisFindings.Count -gt 0) {
    $analysisFindings | Format-Table -AutoSize | Out-String | Write-Information -InformationAction Continue
}

Write-Information "PSScriptAnalyzer Warning/Error findings: $($analysisFindings.Count)" -InformationAction Continue

Write-Information 'Running Pester...' -InformationAction Continue
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $PSScriptRoot
$pesterConfig.Run.PassThru = $true
$pesterConfig.Run.Exit = $false
$pesterConfig.Output.Verbosity = 'Detailed'

$pesterResult = Invoke-Pester -Configuration $pesterConfig

Write-Information "Pester: Passed=$($pesterResult.PassedCount) Failed=$($pesterResult.FailedCount) Skipped=$($pesterResult.SkippedCount)" -InformationAction Continue

if ($analysisFindings.Count -gt 0 -or $pesterResult.FailedCount -gt 0) {
    exit 1
}
