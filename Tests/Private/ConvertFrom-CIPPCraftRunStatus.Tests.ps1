# Craft reports runs app-neutrally; ListCippQueue and the trackers keep the CippQueue shape. The JSON below is
# what QueueStatusBridge.GetRun returns for a 16-tenant fan-out with one failure.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/CippQueue/ConvertFrom-CIPPCraftRunStatus.ps1')

    $script:Run = @'
{"runName":"GraphRequestOrchestrator-f761aa95-044c-4b22-8cb4-fb7938aceb95","reference":"AllTenants-725f6f8c","label":"Users (All Tenants)","link":"/identity/administration/users","status":"CompletedWithErrors","total":16,"queued":0,"running":0,"completed":15,"failed":1,"startedUtc":"2026-10-07T18:16:54.1065695Z","tasks":[{"name":"ListGraphRequestQueue_test02.onmicrosoft.com","status":"Completed","at":"2026-10-07T18:17:24.9944113Z"},{"name":"ListGraphRequestQueue_test01.onmicrosoft.com","status":"Failed","at":"2026-10-07T18:17:00.1164616Z"}]}
'@ | ConvertFrom-Json
}

Describe 'ConvertFrom-CIPPCraftRunStatus' {
    It 'keeps the CippQueue entry shape the trackers and ListCippQueue already use' {
        $Entry = ConvertFrom-CIPPCraftRunStatus -Run $script:Run

        $Entry.PartitionKey | Should -Be 'CippQueue'
        $Entry.RowKey | Should -Be 'GraphRequestOrchestrator-f761aa95-044c-4b22-8cb4-fb7938aceb95'
        $Entry.Name | Should -Be 'Users (All Tenants)'
        $Entry.Link | Should -Be '/identity/administration/users'
        $Entry.Reference | Should -Be 'AllTenants-725f6f8c'
    }

    It 'counts a failed task as done, as the table-backed queue does, and keeps the CIPP status wording' {
        $Entry = ConvertFrom-CIPPCraftRunStatus -Run $script:Run

        $Entry.TotalTasks | Should -Be 16
        $Entry.CompletedTasks | Should -Be 16
        $Entry.FailedTasks | Should -Be 1
        $Entry.PercentComplete | Should -Be 100
        $Entry.PercentFailed | Should -Be 6.3
        $Entry.Status | Should -Be 'Completed (with errors)'
    }

    It 'shows each task by its tenant, not its Function_Tenant job name' {
        $Entry = ConvertFrom-CIPPCraftRunStatus -Run $script:Run

        @($Entry.Tasks.Name) | Should -Be @('test02.onmicrosoft.com', 'test01.onmicrosoft.com')
        @($Entry.Tasks.Status) | Should -Be @('Completed', 'Failed')
    }

    It 'falls back to the run name when no label was registered' {
        $Bare = [pscustomobject]@{ runName = 'Orch-1'; reference = 'Orch-1'; status = 'Queued'; total = 0; tasks = @() }

        $Entry = ConvertFrom-CIPPCraftRunStatus -Run $Bare

        $Entry.Name | Should -Be 'Orch-1'
        $Entry.PercentComplete | Should -Be 0
        @($Entry.Tasks).Count | Should -Be 0
    }
}
