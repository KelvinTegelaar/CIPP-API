BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Start-CIPPOrchestrator { param($InputObject) }
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Tests/Push-CIPPTestsApplyBatch.ps1')

    function New-SuiteTask($Tenant, $Suite) {
        @{ FunctionName = 'CIPPTestCollection'; TenantFilter = $Tenant; SuiteName = $Suite }
    }
}

Describe 'Push-CIPPTestsApplyBatch' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject); "Craft-$($InputObject.OrchestratorName)" }
    }

    It 'starts one sequential run per tenant, keeping suite order' {
        $Item = @{
            Parameters = @{ TenantFilter = 'allTenants' }
            Results    = @(
                , @((New-SuiteTask 'a.com' 'CIS'), (New-SuiteTask 'a.com' 'E8'), (New-SuiteTask 'a.com' 'CISA'))
                , @((New-SuiteTask 'b.com' 'CIS'), (New-SuiteTask 'b.com' 'ORCA'))
            )
        }

        $Result = Push-CIPPTestsApplyBatch -Item $Item

        $Started.Count | Should -Be 2
        $Started.OrchestratorName | Should -Be @('CIPPTestsExecute_allTenants-a.com', 'CIPPTestsExecute_allTenants-b.com')
        $Started.Sequential | Should -Be @($true, $true)
        $Started.DurableMode | Should -Be @('Sequence', 'Sequence')
        $Started[0].Batch.SuiteName | Should -Be @('CIS', 'E8', 'CISA')
        $Started[1].Batch.SuiteName | Should -Be @('CIS', 'ORCA')
        $Result.TaskCount | Should -Be 5
        $Result.InstanceId.Count | Should -Be 2
    }

    It 'keeps the single-tenant run name' {
        $Item = @{
            Parameters = @{ TenantFilter = 'a.com' }
            Results    = @(, @((New-SuiteTask 'a.com' 'CIS'), (New-SuiteTask 'a.com' 'E8')))
        }

        Push-CIPPTestsApplyBatch -Item $Item | Out-Null

        $Started.Count | Should -Be 1
        $Started[0].OrchestratorName | Should -Be 'CIPPTestsExecute_a.com'
        $Started[0].Batch.Count | Should -Be 2
    }

    It 'starts nothing when no tenant produced tasks' {
        $Result = Push-CIPPTestsApplyBatch -Item @{ Results = @(, @()) }

        $Started.Count | Should -Be 0
        $Result.TaskCount | Should -Be 0
    }
}
