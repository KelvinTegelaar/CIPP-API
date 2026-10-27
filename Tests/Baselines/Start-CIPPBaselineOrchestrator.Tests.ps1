BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPBaselineWorkItems { param($TenantFilter, $StandardName, $TemplateId) }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Get-TenantGroups { }
    function Set-CippBaselineRunContext { param($RunId) }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) [pscustomobject]@{ RowKey = 'queue-1' } }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $message, $Sev) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-CIPPBaselineOrchestrator.ps1')

    function New-WorkItem($Tenant, $Standard) {
        [pscustomobject]@{ TenantFilter = $Tenant; Standard = $Standard; BaseName = ($Standard -split '#')[0] }
    }
}

Describe 'Start-CIPPBaselineOrchestrator' {
    BeforeEach {
        Mock Start-CIPPOrchestrator { }
        Mock Get-CIPPBaselineWorkItems {
            New-WorkItem 'contoso.com' 'ConditionalAccessTemplate#a'
            New-WorkItem 'contoso.com' 'ConditionalAccessTemplate#b'
            New-WorkItem 'fabrikam.com' 'ConditionalAccessTemplate#a'
            New-WorkItem 'contoso.com' 'DisableGuests'
        }
    }

    It 'deploys CA templates one at a time per tenant, without collisions, beside the main run' {
        Start-CIPPBaselineOrchestrator -TenantFilter 'contoso.com' -Mode 'oneoff' -TriggeredBy 'tester' -Force | Should -Be 4

        Should -Invoke Start-CIPPOrchestrator -Times 3
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter {
            $InputObject.OrchestratorName -eq 'BaselineRun_oneoff' -and @($InputObject.Batch).Count -eq 1 -and $InputObject.Batch[0].Item.Standard -eq 'DisableGuests' -and -not $InputObject.MaxConcurrency
        }
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter {
            $InputObject.OrchestratorName -eq 'BaselineCA_contoso.com' -and @($InputObject.Batch).Count -eq 2 -and
            $InputObject.MaxConcurrency -eq 1 -and $InputObject.AllowCollision -eq $false -and $InputObject.PostExecution.FunctionName -eq 'CIPPBaselineCacheRefresh'
        }
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter {
            $InputObject.OrchestratorName -eq 'BaselineCA_fabrikam.com' -and @($InputObject.Batch).Count -eq 1 -and $InputObject.MaxConcurrency -eq 1
        }
    }

    It 'skips the main run when only CA templates are queued' {
        Mock Get-CIPPBaselineWorkItems { New-WorkItem 'contoso.com' 'ConditionalAccessTemplate#a' }
        Start-CIPPBaselineOrchestrator -TenantFilter 'contoso.com' -Mode 'oneoff' -TriggeredBy 'tester' -Force | Should -Be 1
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter { $InputObject.OrchestratorName -eq 'BaselineCA_contoso.com' }
    }

    It 'keeps a compare in one run' {
        Start-CIPPBaselineOrchestrator -TenantFilter 'contoso.com' -Mode 'compare' -TriggeredBy 'tester' -Force | Should -Be 4
        Should -Invoke Start-CIPPOrchestrator -Times 1 -ParameterFilter { $InputObject.OrchestratorName -eq 'BaselineRun_compare' -and @($InputObject.Batch).Count -eq 4 }
    }
}
