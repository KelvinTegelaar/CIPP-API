# Pester tests for Get-DeltaQueryUrl
# A DeltaQuery-triggered task and its delta link live in two tables joined only by the task RowKey,
# so the DeltaQueries row can go missing on its own - a restore or instance copy that carried
# ScheduledTasks but not DeltaQueries. Pins the rebuild from the owning task's trigger, and that an
# unrebuildable row still throws rather than returning a null URL.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-DeltaQueryUrl.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-DeltaQueryUrl.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function New-CIPPTaskDeltaQuery { param($Trigger, $TenantFilter, $PartitionKey) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . $FunctionPath

    $script:TaskTrigger = '{"Type":"DeltaQuery","DeltaResource":"users","ResourceFilter":["user-1"],"EventType":"deleted"}'
}

Describe 'Get-DeltaQueryUrl' {
    BeforeEach {
        # Get-CIPPTable hands back the table name as the context, so the entity mock can tell the
        # DeltaQueries lookup apart from the ScheduledTasks lookup.
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-CIPPTaskDeltaQuery -MockWith {
            @{ '@odata.deltaLink' = 'https://graph.microsoft.com/beta/users/delta?$deltatoken=rebuilt' }
        }
    }

    Context 'The delta query row exists' {
        It 'returns the stored DeltaUrl without rebuilding' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [pscustomobject]@{ PartitionKey = 'task-1'; RowKey = 'contoso.com'; DeltaUrl = 'https://stored/deltalink' }
            }

            Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' | Should -Be 'https://stored/deltalink'
            Should -Invoke New-CIPPTaskDeltaQuery -Times 0 -Exactly
        }
    }

    Context 'The delta query row is missing' {
        It 'rebuilds it from the owning task trigger and returns the new link' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Context -eq 'DeltaQueries') { return @() }
                [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; Name = 'Clear Immutable ID: bob'; Trigger = $script:TaskTrigger }
            }

            $Result = Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' 3>$null

            $Result | Should -Be 'https://graph.microsoft.com/beta/users/delta?$deltatoken=rebuilt'
            Should -Invoke New-CIPPTaskDeltaQuery -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq 'contoso.com' -and $PartitionKey -eq 'task-1'
            }
        }

        It 'records that changes before the rebuild were not captured' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Context -eq 'DeltaQueries') { return @() }
                [pscustomobject]@{ RowKey = 'task-1'; Name = 'Clear Immutable ID: bob'; Trigger = $script:TaskTrigger }
            }

            $null = Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' 3>$null

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*not captured*' -and $sev -eq 'Warning' }
        }

        It 'throws when there is no scheduled task to rebuild from' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

            { Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' } |
                Should -Throw -ExpectedMessage '*no scheduled task with a trigger*'
            Should -Invoke New-CIPPTaskDeltaQuery -Times 0 -Exactly
        }

        It 'throws when the owning task has no trigger' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Context -eq 'DeltaQueries') { return @() }
                [pscustomobject]@{ RowKey = 'task-1'; Name = 'no trigger' }
            }

            { Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' } |
                Should -Throw -ExpectedMessage '*no scheduled task with a trigger*'
        }

        It 'propagates a rebuild failure rather than returning nothing' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Context -eq 'DeltaQueries') { return @() }
                [pscustomobject]@{ RowKey = 'task-1'; Name = 'Clear Immutable ID: bob'; Trigger = $script:TaskTrigger }
            }
            Mock -CommandName New-CIPPTaskDeltaQuery -MockWith { throw 'Delta Query failed for tenant.' }

            { Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' 3>$null } |
                Should -Throw -ExpectedMessage '*Delta Query failed for tenant*'
        }

        It 'throws when the rebuild returns no delta link' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                if ($Context -eq 'DeltaQueries') { return @() }
                [pscustomobject]@{ RowKey = 'task-1'; Name = 'Clear Immutable ID: bob'; Trigger = $script:TaskTrigger }
            }
            Mock -CommandName New-CIPPTaskDeltaQuery -MockWith { @{} }

            { Get-DeltaQueryUrl -TenantFilter 'contoso.com' -PartitionKey 'task-1' 3>$null } |
                Should -Throw -ExpectedMessage '*could not be rebuilt*'
        }
    }
}
