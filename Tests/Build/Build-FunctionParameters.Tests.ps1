# Pester tests for build/tools/build-function-parameters.ps1
# Generates a fixture module, runs the generator, dot-sources the same fixture and
# asserts the synthesized synopses match live Get-Help byte for byte. Covers the
# constructs that broke earlier revisions: mixed explicit positions, named parameter
# sets, ghost default sets, positioned switches, non-$true mandatory literals.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $GeneratorPath = Join-Path (Split-Path -Parent $RepoRoot) 'build/tools/build-function-parameters.ps1'
    if (-not (Test-Path $GeneratorPath)) { throw "Could not locate build-function-parameters.ps1 at $GeneratorPath" }

    $FixtureRoot = Join-Path $TestDrive 'FixtureModule'
    $PublicDir = Join-Path $FixtureRoot 'Public'
    $null = New-Item -ItemType Directory -Path $PublicDir -Force

    $FixtureSource = @'
function Test-AutoPositional {
    param($User, [string]$Name, [switch]$Force)
}
function Test-MandatoryForms {
    param(
        [Parameter(Mandatory)][string]$FlagForm,
        [Parameter(Mandatory = $true)]$ExplicitTrue,
        [Parameter(Mandatory = 1)][string]$NumericTrue,
        [Parameter(Mandatory = $false)]$ExplicitFalse
    )
}
function Test-MixedPositions {
    [CmdletBinding()]
    param(
        [Parameter(Position = 1)][string]$Second,
        [Parameter(Position = 0)][string]$First,
        [Parameter()][string]$Named
    )
}
function Test-NamedSets {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Single', Mandatory)][string]$UserId,
        [Parameter(ParameterSetName = 'Single')][string]$Nickname,
        [Parameter(ParameterSetName = 'Bulk', Mandatory)][System.Collections.Generic.List[object]]$Requests,
        [Parameter(Mandatory)][string]$TenantFilter,
        $Headers
    )
}
function Test-SwitchInNamedSet {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'A')][switch]$Sw,
        [Parameter(ParameterSetName = 'A')][string]$S
    )
}
function Test-PositionedSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][switch]$Sw,
        [Parameter(Position = 1)][string]$Str
    )
}
function Test-GhostDefault {
    [CmdletBinding(DefaultParameterSetName = 'Nope')]
    param(
        [Parameter(ParameterSetName = 'A')][string]$X,
        [Parameter(ParameterSetName = 'B')][string]$Y
    )
}
function Test-ShouldProcess {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Target)
}
function Test-WithCommentHelp {
    <#
    .SYNOPSIS
    a real synopsis
    .FUNCTIONALITY
    Internal
    .PARAMETER Thing
    the thing
    #>
    param([string]$Thing)
}
'@
    Set-Content -Path (Join-Path $PublicDir 'fixtures.ps1') -Value $FixtureSource

    $OutputPath = Join-Path $TestDrive 'out.json'
    & $GeneratorPath -ModulePath $FixtureRoot -OutputPath $OutputPath | Out-Null
    $script:Generated = Get-Content $OutputPath -Raw | ConvertFrom-Json -AsHashtable

    # same definitions live in the session so Get-Help renders its real synopses
    . (Join-Path $PublicDir 'fixtures.ps1')

    $script:NoHelpFunctions = @(
        'Test-AutoPositional', 'Test-MandatoryForms', 'Test-MixedPositions', 'Test-NamedSets',
        'Test-SwitchInNamedSet', 'Test-PositionedSwitch', 'Test-GhostDefault', 'Test-ShouldProcess'
    )
}

Describe 'build-function-parameters generator' {
    It 'synthesizes a synopsis byte-identical to Get-Help for <_>' -ForEach @(
        'Test-AutoPositional', 'Test-MandatoryForms', 'Test-MixedPositions', 'Test-NamedSets',
        'Test-SwitchInNamedSet', 'Test-PositionedSwitch', 'Test-GhostDefault', 'Test-ShouldProcess'
    ) {
        $expected = (Get-Help $_).Synopsis.Trim()
        # Get-Help joins multi-set blocks with the platform newline; the cache pins CRLF
        $normalizedGenerated = $script:Generated[$_]['Synopsis'] -replace "`r`n", "`n"
        $normalizedExpected = $expected -replace "`r`n", "`n"
        $normalizedGenerated | Should -BeExactly $normalizedExpected
    }

    It 'extracts comment-based help instead of synthesizing' {
        $script:Generated['Test-WithCommentHelp']['Synopsis'] | Should -Be 'a real synopsis'
        $script:Generated['Test-WithCommentHelp']['Functionality'] | Should -Be 'Internal'
        ($script:Generated['Test-WithCommentHelp']['Parameters'] | Where-Object { $_['Name'] -eq 'Thing' })['Description'] | Should -Be 'the thing'
    }

    It 'marks non-$true mandatory literals as required' {
        $params = @{}
        foreach ($p in $script:Generated['Test-MandatoryForms']['Parameters']) { $params[$p['Name']] = $p['Required'] }
        $params['FlagForm'] | Should -BeTrue
        $params['ExplicitTrue'] | Should -BeTrue
        $params['NumericTrue'] | Should -BeTrue
        $params['ExplicitFalse'] | Should -BeFalse
    }

    It 'fails the build when a source file cannot be parsed' {
        $brokenRoot = Join-Path $TestDrive 'BrokenModule'
        $null = New-Item -ItemType Directory -Path (Join-Path $brokenRoot 'Public') -Force
        Set-Content -Path (Join-Path $brokenRoot 'Public/ok.ps1') -Value 'function Get-Ok { param($A) }'
        Set-Content -Path (Join-Path $brokenRoot 'Public/broken.ps1') -Value 'function Get-Broken {{{'
        { & $GeneratorPath -ModulePath $brokenRoot -OutputPath (Join-Path $TestDrive 'broken-out.json') } | Should -Throw '*failed to parse*'
    }
}
