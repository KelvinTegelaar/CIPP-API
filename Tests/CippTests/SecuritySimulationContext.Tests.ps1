BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue
    . (Join-Path $RepoRoot 'Modules/CIPPTests/Public/Helpers/Get-CippSecuritySimulationContext.ps1')

    $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('secsim-' + [guid]::NewGuid().ToString('N'))
    $ScenarioDir = Join-Path $script:Root 'Modules/CIPPTests/Public/Tests/SecuritySimulations'
    $null = New-Item -ItemType Directory -Path $ScenarioDir -Force
    Set-Content -Path (Join-Path $ScenarioDir 'scenarios.json') -Value '[{"id":"S1","steps":[{"id":"a","standards":[{"name":"PerUserMFA"},{"name":"WithVars"}]}]}]'
    $script:OldRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $script:Root

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:Rows }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Test-CIPPStandardLicense { $true }
    function Get-CIPPBaselineDefinition { param($Name) $script:Definitions[$Name] }
    function Invoke-CIPPBaselineStandard { param($Item, $Mode, [switch]$GradeOnly) [pscustomobject]@{ Compliant = $false; CurrentValue = 1; Diff = @([pscustomobject]@{ Property = 'live' }) } }

    $script:Definitions = @{
        PerUserMFA = [pscustomobject]@{ name = 'PerUserMFA'; label = 'Per user MFA'; variables = [pscustomobject]@{}; expected = [pscustomobject]@{ offenders = @() }; prepare = 'Get-CIPPBaselinePerUserMFAState' }
        WithVars   = [pscustomobject]@{ name = 'WithVars'; label = 'With vars'; variables = [pscustomobject]@{ days = [pscustomobject]@{ default = 30 } }; expected = [pscustomobject]@{ days = '%days%' } }
    }
    function New-Row($Name, $Status, [double]$HoursAgo = 1, [bool]$Pending = $false, $Diff = '[]') {
        [pscustomobject]@{ StandardName = $Name; Status = $Status; LastRun = [DateTimeOffset]::UtcNow.AddHours(-$HoursAgo).ToUnixTimeSeconds(); PendingVerification = $Pending; Diff = $Diff }
    }
    function Get-State($Name) { $Context = Get-CippSecuritySimulationContext -Tenant 't.com'; $Context.Standards.Values.Where({ $_.name -eq $Name })[0] }
}

AfterAll {
    $env:CIPPRootPath = $script:OldRoot
    Remove-Item -Path $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-CippSecuritySimulationContext baseline reuse' {
    BeforeEach {
        $script:CippSecuritySimulationContext = $null
        Mock Invoke-CIPPBaselineStandard { [pscustomobject]@{ Compliant = $false; CurrentValue = 1; Diff = @([pscustomobject]@{ Property = 'live' }) } }
    }

    It 'takes a recent Compliant verdict for a standard without settings instead of grading it' {
        $script:Rows = @(New-Row 'PerUserMFA' 'Compliant')
        $State = Get-State 'PerUserMFA'
        $State.status | Should -Be 'Compliant'
        $State.compliant | Should -BeTrue
        $State.assigned | Should -BeTrue
        Should -Invoke Invoke-CIPPBaselineStandard -Times 0 -ParameterFilter { $Item.Standard -eq 'PerUserMFA' }
    }

    It 'turns a recent Drift verdict into the same detail a live grade writes' {
        $script:Rows = @(New-Row 'PerUserMFA' 'Drift' -Diff '[{"Property":"offenders.0"},{"Property":"offenders.1"},{"Property":"offenders.0"},{"Property":""}]')
        $State = Get-State 'PerUserMFA'
        $State.status | Should -Be 'Not configured'
        $State.compliant | Should -BeFalse
        $State.detail | Should -Be 'Differs on: offenders.0, offenders.1'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 0 -ParameterFilter { $Item.Standard -eq 'PerUserMFA' }
    }

    It 'grades live when the verdict is <Case>' -ForEach @(
        @{ Case = 'older than 12 hours'; Row = { New-Row 'PerUserMFA' 'Compliant' -HoursAgo 13 } }
        @{ Case = 'pending verification'; Row = { New-Row 'PerUserMFA' 'Compliant' -Pending $true } }
        @{ Case = 'an accepted deviation'; Row = { New-Row 'PerUserMFA' 'Accepted' } }
        @{ Case = 'No Data'; Row = { New-Row 'PerUserMFA' 'No Data' } }
    ) {
        $script:Rows = @(& $Row)
        $null = Get-State 'PerUserMFA'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -ParameterFilter { $Item.Standard -eq 'PerUserMFA' }
    }

    It 'grades a standard with settings live even with a recent verdict, because the baseline may use other values' {
        $script:Rows = @(New-Row 'WithVars' 'Compliant')
        $State = Get-State 'WithVars'
        $State.detail | Should -Be 'Differs on: live'
        Should -Invoke Invoke-CIPPBaselineStandard -Times 1 -ParameterFilter { $Item.Standard -eq 'WithVars' }
    }
}
