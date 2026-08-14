# Pester tests for the DeltaQuery branch of Add-CIPPScheduledTask
# A DeltaQuery-triggered task is worthless without its DeltaQueries row: every dispatch fails the
# lookup in Get-DeltaQueryUrl. Pins that a delta query failure fails the task creation rather than
# persisting an orphan, and that the delta query is keyed by the new task's RowKey.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Add-CIPPScheduledTask.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Add-CIPPScheduledTask.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CippQueueMessage { param($Cmdlet, $Parameters) }
    function New-CIPPTaskDeltaQuery { param($Trigger, $TenantFilter, $PartitionKey) }
    function Get-CIPPSchedulerBlockedCommands { }
    function Get-NormalizedError { param($Message) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $Tenant) }

    . $FunctionPath

    function New-DeltaTaskRequest {
        param([string]$DeltaResource = 'users')
        [pscustomobject]@{
            TenantFilter  = 'contoso.com'
            Name          = 'Clear Immutable ID: bob'
            Command       = @{ value = 'Clear-CIPPImmutableID' }
            Parameters    = [pscustomobject]@{ UserID = 'user-1'; TenantFilter = 'contoso.com' }
            Trigger       = @{
                Type               = 'DeltaQuery'
                DeltaResource      = $DeltaResource
                ResourceFilter     = @('user-1')
                EventType          = 'deleted'
                ExecutePerResource = $true
                ExecutionMode      = 'once'
            }
            ScheduledTime = 0
            Recurrence    = '15m'
            PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
        }
    }
}

Describe 'Add-CIPPScheduledTask DeltaQuery trigger' {
    BeforeEach {
        $script:Persisted = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'ScheduledTasks' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Persisted.Add($Entity) }
        Mock -CommandName Add-CippQueueMessage -MockWith { }
        Mock -CommandName Get-CIPPSchedulerBlockedCommands -MockWith { @() }
        Mock -CommandName Get-NormalizedError -MockWith { $Message }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-CIPPTaskDeltaQuery -MockWith { @{ '@odata.deltaLink' = 'https://graph/deltalink' } }
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'Clear-CIPPImmutableID' } -MockWith {
            [pscustomobject]@{ Name = 'Clear-CIPPImmutableID'; Module = 'CIPPCore'; Parameters = @{ TenantFilter = 1; UserID = 1 } }
        }
    }

    Context 'The delta query is created' {
        It 'persists the task and keys the delta query by its RowKey' {
            $Result = Add-CIPPScheduledTask -Task (New-DeltaTaskRequest) -hidden $true

            $Result | Should -BeLike 'Successfully added task*'
            $script:Persisted.Count | Should -Be 1
            Should -Invoke New-CIPPTaskDeltaQuery -Times 1 -Exactly
            $script:Persisted[0].RowKey | Should -Not -BeNullOrEmpty
        }

        It 'creates the delta query before the task row is written' {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName New-CIPPTaskDeltaQuery -MockWith {
                $script:Order.Add('delta')
                @{ '@odata.deltaLink' = 'https://graph/deltalink' }
            }
            Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Order.Add('task') }

            $null = Add-CIPPScheduledTask -Task (New-DeltaTaskRequest) -hidden $true

            $script:Order -join ',' | Should -Be 'delta,task'
        }
    }

    Context 'The delta query cannot be created' {
        BeforeEach {
            Mock -CommandName New-CIPPTaskDeltaQuery -MockWith { throw 'Delta Query failed for tenant.' }
        }

        It 'does not persist an orphaned task row' {
            { Add-CIPPScheduledTask -Task (New-DeltaTaskRequest) -hidden $true } | Should -Throw
            $script:Persisted.Count | Should -Be 0
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'surfaces the delta query error to the caller' {
            { Add-CIPPScheduledTask -Task (New-DeltaTaskRequest) -hidden $true } |
                Should -Throw -ExpectedMessage '*Delta Query failed for tenant*'
        }
    }

    Context 'A task with no trigger' {
        It 'is persisted without touching the delta query path' {
            $Task = New-DeltaTaskRequest
            $Task.PSObject.Properties.Remove('Trigger')

            $null = Add-CIPPScheduledTask -Task $Task -hidden $true

            $script:Persisted.Count | Should -Be 1
            Should -Invoke New-CIPPTaskDeltaQuery -Times 0 -Exactly
        }
    }
}
