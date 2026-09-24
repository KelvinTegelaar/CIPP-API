# User-clicked orchestrations must land in their own bucket ahead of the P2 scheduled-task
# band; the queue claims strictly by bucket, so sharing P2 put a click behind every fan-out.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Resolve-CIPPOrchestratorPriority.ps1')
}

Describe 'Resolve-CIPPOrchestratorPriority' {
    It 'uses an explicit in-range priority' {
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{ Priority = 3 }) -OpContext $null | Should -Be 3
    }

    It 'ignores an out-of-range explicit priority and falls back' {
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{ Priority = -1 }) -OpContext $null | Should -Be 4
    }

    It 'inherits the enclosing run band from the stamped context' {
        $Ctx = [pscustomobject]@{ Category = 'Job'; Priority = 2; RunName = 'UserTaskOrchestrator_x' }
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{}) -OpContext $Ctx | Should -Be 2
    }

    It 'gives HTTP-triggered work P1, ahead of the scheduled-task band' {
        $Ctx = [pscustomobject]@{ Category = 'HTTP'; Priority = $null; RunName = $null }
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{}) -OpContext $Ctx | Should -Be 1
    }

    It 'defaults background starters to P4' {
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{}) -OpContext $null | Should -Be 4
        Resolve-CIPPOrchestratorPriority -InputObject ([pscustomobject]@{}) -OpContext ([pscustomobject]@{ Category = 'Job'; Priority = $null }) | Should -Be 4
    }
}
