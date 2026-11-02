BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPDBCacheApplyBatch.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Resolve-CIPPOrchestratorPriority.ps1')
    function Start-CIPPOrchestrator { param($InputObject) }

    function New-ApplyBatchItem ([string]$TenantFilter, [string[]]$Tenants = @('contoso.com')) {
        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Tenant in $Tenants) {
            $Batch = [System.Collections.Generic.List[object]]::new()
            foreach ($Type in 'Graph', 'Intune', 'ExchangeConfig') {
                $Batch.Add(@{ FunctionName = 'ExecCIPPDBCache'; CollectionType = $Type; TenantFilter = $Tenant })
            }
            $TenantResult = [System.Collections.Generic.List[object]]::new(); $TenantResult.Add($Batch)
            $Results.Add($TenantResult)
        }
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
        $script:Runs[1].PSObject.Properties.Name | Should -Not -Contain 'Priority'
        @($script:Runs[1].Batch.CollectionType) | Should -Be @('Graph', 'ExchangeConfig')
        $script:Runs.AllowCollision | Should -Be @($false, $false)
    }

    It 'starts one capped run per tenant so a tenant never has more than two groups in flight' {
        $Result = Push-CIPPDBCacheApplyBatch -Item (New-ApplyBatchItem -Tenants 'contoso.com', 'fabrikam.com')

        $Tenant = @($script:Runs | Where-Object OrchestratorName -NE 'CIPPDBCacheExecuteIntune')
        @($Tenant.OrchestratorName) | Should -Be @('CIPPDBCacheExecute-contoso.com', 'CIPPDBCacheExecute-fabrikam.com')
        $Tenant | ForEach-Object { $_.MaxConcurrency | Should -Be 2; $_.AllowCollision | Should -BeFalse }
        @($Tenant[0].Batch.TenantFilter | Sort-Object -Unique) | Should -Be @('contoso.com')
        @($Tenant[1].Batch.TenantFilter | Sort-Object -Unique) | Should -Be @('fabrikam.com')
        @($Tenant[1].Batch.CollectionType) | Should -Be @('Graph', 'ExchangeConfig')
        $Result.TaskCount | Should -Be 4
        @($Result.InstanceId).Count | Should -Be 2
    }

    It 'gives a single-tenant refresh the same capped per-tenant run as the nightly' {
        Push-CIPPDBCacheApplyBatch -Item (New-ApplyBatchItem -TenantFilter 'contoso.com') | Out-Null

        @($script:Runs.OrchestratorName) | Should -Be @('CIPPDBCacheExecuteIntune', 'CIPPDBCacheExecute-contoso.com')
        $script:Runs[1].MaxConcurrency | Should -Be 2
        @($script:Runs[1].Batch.CollectionType) | Should -Be @('Graph', 'ExchangeConfig')
        $script:Runs[1].PSObject.Properties.Name | Should -Not -Contain 'PostExecution'
    }

    It 'keeps Intune in the tenant run of a test refresh and chains the tests after it' {
        $Item = New-ApplyBatchItem -TenantFilter 'contoso.com'
        $Item.Parameters.TestRun = $true
        Push-CIPPDBCacheApplyBatch -Item $Item | Out-Null

        $script:Runs.Count | Should -Be 1
        $script:Runs[0].OrchestratorName | Should -Be 'CIPPDBCacheExecute-contoso.com'
        $script:Runs[0].MaxConcurrency | Should -Be 2
        @($script:Runs[0].Batch.CollectionType) | Should -Be @('Graph', 'Intune', 'ExchangeConfig')
        $script:Runs[0].PostExecution.FunctionName | Should -Be 'CIPPDBTestsRun'
        $script:Runs[0].PostExecution.Parameters.TenantFilter | Should -Be 'contoso.com'
    }
}
