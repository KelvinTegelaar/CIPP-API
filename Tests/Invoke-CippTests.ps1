#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the CIPP-API Pester test suite.

.DESCRIPTION
    Thin, opinionated wrapper around Pester 5 so the backend tests can be run with a
    single command regardless of the caller's current directory. Pester only discovers
    files named '*.Tests.ps1', so the non-Pester helper scripts that also live under
    Tests/ (Test-ODataFilterInjection.ps1, Test-SchedulerBlocklist.ps1) are ignored
    automatically.

.PARAMETER Path
    Limit the run to a specific test file or folder (relative to the repo root or absolute).
    Defaults to the entire Tests/ directory.

.PARAMETER Tag
    Only run It/Describe blocks carrying one of these Pester tags.

.PARAMETER CI
    Emit a NUnit result file (Tests/TestResults.xml). Use this from automation / GitHub Actions.
    Note: a non-zero exit on failure is the DEFAULT (not gated on -CI) - see -NoExitCode.

.PARAMETER NoExitCode
    Do not set the process exit code from the test result. Use this in an interactive session
    where a failing run should not terminate your shell. By default the script exits with the
    failed-test count so scripts/agents relying on process status see red as red.

.PARAMETER Coverage
    Also collect code coverage over Modules/**/Public and write Tests/coverage.xml.

.EXAMPLE
    pwsh CIPP-API/Tests/Invoke-CippTests.ps1
    Runs the whole suite with detailed console output.

.EXAMPLE
    pwsh CIPP-API/Tests/Invoke-CippTests.ps1 -Path Tests/Endpoint -CI
    Runs only the Endpoint tests and produces a CI result file + exit code.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [string[]]$Tag,
    [switch]$CI,
    [switch]$NoExitCode,
    [switch]$Coverage
)

$ErrorActionPreference = 'Stop'

# Tests/ is one level under the repo root.
$TestsRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $TestsRoot

# Pester 5 is required for the Should -Invoke / -ParameterFilter syntax the suite uses.
$pester = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    throw "Pester 5+ is required but was not found. Install it with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser"
}
Import-Module $pester -ErrorAction Stop

# Resolve -Path entries against the repo root when they are not already absolute,
# so callers can pass repo-relative paths like 'Tests/Endpoint' from anywhere.
$runPaths = if ($Path) {
    foreach ($p in $Path) {
        if ([System.IO.Path]::IsPathRooted($p)) { $p }
        elseif (Test-Path -LiteralPath (Join-Path $RepoRoot $p)) { Join-Path $RepoRoot $p }
        else { $p }
    }
} else {
    $TestsRoot
}

$config = New-PesterConfiguration
$config.Run.Path = $runPaths
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

if ($Tag) {
    $config.Filter.Tag = $Tag
}

if ($CI) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = Join-Path $TestsRoot 'TestResults.xml'
}

if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path $RepoRoot 'Modules'
    $config.CodeCoverage.OutputPath = Join-Path $TestsRoot 'coverage.xml'
}

$result = Invoke-Pester -Configuration $config

# Surface a real exit code by default so agents / pipelines that key off process status
# see a red suite as red. -NoExitCode opts out for interactive shells.
if (-not $NoExitCode) {
    exit $result.FailedCount
}
