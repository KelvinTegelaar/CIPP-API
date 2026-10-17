BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Mailbox Permissions/Push-StoreMailboxData.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Start-CIPPMailboxDataStage.ps1')
    function Push-StoreMailboxPermissions { param($Item) }
    function Push-StoreMailboxRules { param($Item) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Update-CippQueueEntry { param($RowKey, $TotalTasks, [switch]$IncrementTotalTasks) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    function New-StageItem ([string]$Type, [string[]]$Remaining) {
        @{ Parameters = @{ TenantFilter = 'contoso.com'; Type = $Type; Remaining = $Remaining; QueueId = 'q1' }; Results = @(@{ 'Get-MailboxPermission' = @() }) }
    }
}

Describe 'Push-StoreMailboxData' {
    BeforeEach {
        $script:Runs = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Runs.Add($InputObject) }
        Mock Push-StoreMailboxPermissions {}
        Mock Push-StoreMailboxRules {}
        Mock Update-CippQueueEntry {}
        Mock Write-LogMessage {}
        Mock New-CIPPDbRequest { 1..400 | ForEach-Object { [pscustomobject]@{ UPN = "u$_@contoso.com" } } }
    }

    It 'stores the permissions stage, then starts the calendar stage from the cached mailbox list' {
        Push-StoreMailboxData -Item (New-StageItem 'Permissions' @('CalendarPermissions', 'Rules'))

        Should -Invoke Push-StoreMailboxPermissions -Times 1 -Exactly
        Should -Invoke Push-StoreMailboxRules -Times 0 -Exactly
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $Type -eq 'Mailboxes' -and $Fields -contains 'UPN' }
        $script:Runs.Count | Should -Be 1
        $Run = $script:Runs[0]
        $Run.OrchestratorName | Should -Be 'CalendarPermissions_contoso.com'
        $Run.MaxConcurrency | Should -Be 1
        @($Run.Batch.FunctionName | Sort-Object -Unique) | Should -Be @('GetCalendarPermissionsBatch')
        @($Run.Batch | ForEach-Object { @($_.Mailboxes).Count }) | Should -Be @(320, 80)
        @($Run.Batch.QueueId | Sort-Object -Unique) | Should -Be @('q1')
        $Run.PostExecution.Parameters.Type | Should -Be 'CalendarPermissions'
        $Run.PostExecution.Parameters.Batches | Should -Be 2
        @($Run.PostExecution.Parameters.Remaining) | Should -Be @('Rules')
    }

    It 'stores calendar results through the permission store, then starts rules' {
        Push-StoreMailboxData -Item (New-StageItem 'CalendarPermissions' @('Rules'))

        Should -Invoke Push-StoreMailboxPermissions -Times 1 -Exactly
        $script:Runs[0].OrchestratorName | Should -Be 'MailboxRules_contoso.com'
        $script:Runs[0].MaxConcurrency | Should -Be 2
        @($script:Runs[0].Batch.FunctionName | Sort-Object -Unique) | Should -Be @('GetMailboxRulesBatch')
        @($script:Runs[0].PostExecution.Parameters.Remaining).Count | Should -Be 0
    }

    It 'ends the chain after the last stage' {
        Push-StoreMailboxData -Item (New-StageItem 'Rules' @())

        Should -Invoke Push-StoreMailboxRules -Times 1 -Exactly
        Should -Invoke Push-StoreMailboxPermissions -Times 0 -Exactly
        $script:Runs.Count | Should -Be 0
    }

    It 'moves on to the next stage when a run of this type is already going' {
        Mock Start-CIPPOrchestrator {
            $script:Runs.Add($InputObject)
            if ($InputObject.OrchestratorName -like 'CalendarPermissions_*') { "Craft-$($InputObject.OrchestratorName)-Skipped" } else { 'Craft-started' }
        }

        Push-StoreMailboxData -Item (New-StageItem 'Permissions' @('CalendarPermissions', 'Rules'))

        @($script:Runs.OrchestratorName) | Should -Be @('CalendarPermissions_contoso.com', 'MailboxRules_contoso.com')
        @($script:Runs[1].PostExecution.Parameters.Remaining).Count | Should -Be 0
        Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $TotalTasks -eq 2 }
    }

    It 'still starts the next stage when storing this one fails' {
        Mock Push-StoreMailboxPermissions { throw 'table unavailable' }

        Push-StoreMailboxData -Item (New-StageItem 'Permissions' @('Rules'))

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like '*Permissions*table unavailable*' }
        $script:Runs[0].OrchestratorName | Should -Be 'MailboxRules_contoso.com'
    }

    It 'keeps the previous cache when a batch failed, and still starts the next stage' {
        $Item = New-StageItem 'CalendarPermissions' @('Rules')
        $Item.Parameters.Batches = 2

        Push-StoreMailboxData -Item $Item

        Should -Invoke Push-StoreMailboxPermissions -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '1 of 2 CalendarPermissions batches failed*' }
        $script:Runs[0].OrchestratorName | Should -Be 'MailboxRules_contoso.com'
    }

    It 'stores when every batch returned' {
        $Item = New-StageItem 'Rules' @()
        $Item.Parameters.Batches = 1

        Push-StoreMailboxData -Item $Item

        Should -Invoke Push-StoreMailboxRules -Times 1 -Exactly
    }
}
