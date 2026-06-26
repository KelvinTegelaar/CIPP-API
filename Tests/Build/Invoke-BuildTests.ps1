#Requires -Version 7.0
<#
.SYNOPSIS
    Runs static analysis and the OpenAPI response schema Pester suite.

.DESCRIPTION
    Conventional one-command verification for the response schema build stage.
    Checks PSScriptAnalyzer warning and error findings for the stage script and
    its tests, then runs the focused Pester 5 suite. Exits non-zero on failure.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repoRoot '.build' 'Add-OpenApiResponseSchemas.ps1'
$testPath = Join-Path $PSScriptRoot 'Add-OpenApiResponseSchemas.Tests.ps1'

Write-Information 'Running PSScriptAnalyzer...' -InformationAction Continue
$analysisFindings = @(
    foreach ($path in @($scriptPath, $testPath)) {
        Invoke-ScriptAnalyzer -Path $path -Severity Warning, Error
    }
)

if ($analysisFindings.Count -gt 0) {
    $analysisFindings | Format-Table -AutoSize | Out-String | Write-Information -InformationAction Continue
}

Write-Information "PSScriptAnalyzer Warning/Error findings: $($analysisFindings.Count)" -InformationAction Continue

Write-Information 'Running Pester...' -InformationAction Continue
$pesterConfig = New-PesterConfiguration
$pesterConfig.Run.Path = $testPath
$pesterConfig.Run.PassThru = $true
$pesterConfig.Run.Exit = $false
$pesterConfig.Output.Verbosity = 'Detailed'

$pesterResult = Invoke-Pester -Configuration $pesterConfig

Write-Information "Pester: Passed=$($pesterResult.PassedCount) Failed=$($pesterResult.FailedCount) Skipped=$($pesterResult.SkippedCount)" -InformationAction Continue

if ($analysisFindings.Count -gt 0 -or $pesterResult.FailedCount -gt 0) {
    exit 1
}
