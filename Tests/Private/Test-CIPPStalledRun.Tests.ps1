# Pester tests for Test-CIPPStalledRun
# The run summary carries no status field, so the stall predicate is the only thing standing
# between a wedged orchestrator run and a silent PASS. These tests pin each clause.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPStalledRun.ps1')

    $script:Now = [DateTime]::Parse('2026-09-10T12:00:00Z').ToUniversalTime()
    function New-Run {
        param($Running, $Queued, $StartedUtc, $CompletedUtc)
        [PSCustomObject]@{
            Name         = 'StandardsOrchestrator'
            Running      = $Running
            Queued       = $Queued
            StartedUtc   = $StartedUtc
            CompletedUtc = $CompletedUtc
        }
    }
}

Describe 'Test-CIPPStalledRun' {
    It 'flags an active run with queued work, nothing running and a start over 2h old' {
        $Run = New-Run -Running 0 -Queued 12 -StartedUtc $script:Now.AddHours(-3) -CompletedUtc $null
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeTrue
    }

    It 'does not flag a run that is still doing work' {
        $Run = New-Run -Running 2 -Queued 12 -StartedUtc $script:Now.AddHours(-3) -CompletedUtc $null
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeFalse
    }

    It 'does not flag a run with nothing left queued' {
        $Run = New-Run -Running 0 -Queued 0 -StartedUtc $script:Now.AddHours(-3) -CompletedUtc $null
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeFalse
    }

    It 'does not flag a completed run' {
        $Run = New-Run -Running 0 -Queued 12 -StartedUtc $script:Now.AddHours(-3) -CompletedUtc $script:Now.AddHours(-1)
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeFalse
    }

    It 'does not flag a run that started an hour ago' {
        $Run = New-Run -Running 0 -Queued 12 -StartedUtc $script:Now.AddHours(-1) -CompletedUtc $null
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeFalse
    }

    It 'does not flag a run that has not started' {
        $Run = New-Run -Running 0 -Queued 12 -StartedUtc $null -CompletedUtc $null
        Test-CIPPStalledRun -Run $Run -Now $script:Now | Should -BeFalse
    }
}
