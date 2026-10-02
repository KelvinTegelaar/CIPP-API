BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPDBCacheApplyBatch.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Resolve-CIPPOrchestratorPriority.ps1')
    function Start-CIPPOrchestrator { param($InputObject) }

    function New-ApplyBatchItem ([string]$TenantFilter) {
        $Batch = [System.Collections.Generic.List[object]]::new()
        foreach ($Type in 'Graph', 'Intune', 'ExchangeConfig') {
            $Batch.Add(@{ FunctionName = 'ExecCIPPDBCache'; CollectionType = $Type; TenantFilter = 'contoso.com' })
        }
        $TenantResult = [System.Collections.Generic.List[object]]::new(); $TenantResult.Add($Batch)
        $Results = [System.Collections.Generic.List[object]]::new(); $Results.Add($TenantResult)
        [pscustomobject]@{ Results = $Results; Parameters = @{ TenantFilter = $TenantFilter } }
    }
}

Describe 'Push-CIPPDBCacheApplyBatch' {
    BeforeEach {
        $script:Runs = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Runs.Add($InputObject); "run-$($script:Runs.Count)" }
        $global:CraftOperationContext = [pscustomobject]@{ Category = 'Orchestrator'; Priority = 10 }
    }
    AfterAll { Remove-Variable -Name CraftOperationContext -Scope Global -ErrorAction SilentlyContinue }

    It 'starts the Intune group as its own run one band ahead of the rest of the nightly cache' {
        Push-CIPPDBCacheApplyBatch -Item (New-ApplyBatchItem) | Out-Null

        $script:Runs.Count | Should -Be 2
        $script:Runs[0].OrchestratorName | Should -Be 'CIPPDBCacheExecuteIntune'
        $script:Runs[0].Priority | Should -Be 9
        @($script:Runs[0].Batch.CollectionType) | Should -Be @('Intune')
        $script:Runs[1].OrchestratorName | Should -Be 'CIPPDBCacheExecute'
        $script:Runs[1].PSObject.Properties.Name | Should -Not -Contain 'Priority'
        @($script:Runs[1].Batch.CollectionType) | Should -Be @('Graph', 'ExchangeConfig')
    }

    It 'keeps a single-tenant run whole' {
        Push-CIPPDBCacheApplyBatch -Item (New-ApplyBatchItem -TenantFilter 'contoso.com') | Out-Null

        $script:Runs.Count | Should -Be 1
        $script:Runs[0].OrchestratorName | Should -Be 'CIPPDBCacheExecute_contoso.com'
        @($script:Runs[0].Batch).Count | Should -Be 3
    }
}
